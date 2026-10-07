using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using TaleWorlds.Library;

namespace SkirmishPlay.Stats
{
    internal sealed class SupabaseStatsClient : IDisposable
    {
        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };

        private readonly StatsConfig _config;
        private readonly HttpClient _http;
        private readonly ConcurrentQueue<Func<CancellationToken, Task>> _queue = new ConcurrentQueue<Func<CancellationToken, Task>>();
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private readonly Task _worker;
        private readonly string _fallbackPath;
        private bool _disposed;
        private int _dropLogCount;
        private const int MaxQueuedJobs = 400;
        private const int MaxFallbackBytes = 8 * 1024 * 1024;

        public SupabaseStatsClient(StatsConfig config)
        {
            _config = config ?? throw new ArgumentNullException(nameof(config));
            _http = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(20),
                BaseAddress = new Uri(TrimSlash(config.SupabaseUrl) + "/"),
            };
            _http.DefaultRequestHeaders.Add("apikey", config.ServiceRoleKey);
            _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", config.ServiceRoleKey);
            _http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            _fallbackPath = ResolveFallbackPath();
            _worker = Task.Run(() => WorkerLoopAsync(_cts.Token));
        }

        public void EnqueueUpsertMatch(MatchRow match, bool preferUpdate)
        {
            Enqueue(async ct =>
            {
                string json = JsonSerializer.Serialize(match, JsonOptions);
                if (preferUpdate)
                {
                    await PatchAsync($"rest/v1/matches?id=eq.{match.Id}", json, ct).ConfigureAwait(false);
                }
                else
                {
                    await PostAsync("rest/v1/matches", json, preferResolution: "resolution=merge-duplicates", ct).ConfigureAwait(false);
                }
            }, "upsert_match", match);
        }

        public void EnqueueRoundPlayer(RoundPlayerRpcPayload payload)
        {
            Enqueue(async ct =>
            {
                string json = JsonSerializer.Serialize(payload, JsonOptions);
                await PostAsync("rest/v1/rpc/upsert_career_from_round", json, preferResolution: null, ct).ConfigureAwait(false);
            }, "round_player", payload);
        }

        private void Enqueue(Func<CancellationToken, Task> work, string kind, object payload)
        {
            if (!_config.IsReady || _disposed)
            {
                return;
            }

            if (_queue.Count >= MaxQueuedJobs)
            {
                _dropLogCount++;
                if (_dropLogCount <= 3 || (_dropLogCount % 50) == 0)
                {
                    Debug.Print($"[SkirmishPlay.Stats] Dropping {kind} (queue={_queue.Count}, drops={_dropLogCount}).");
                }

                return;
            }

            _queue.Enqueue(async ct =>
            {
                const int maxAttempts = 3;
                Exception? last = null;
                for (int attempt = 1; attempt <= maxAttempts; attempt++)
                {
                    try
                    {
                        await work(ct).ConfigureAwait(false);
                        return;
                    }
                    catch (Exception ex) when (!ct.IsCancellationRequested)
                    {
                        last = ex;
                        Debug.Print($"[SkirmishPlay.Stats] {kind} attempt {attempt}/{maxAttempts} failed: {Truncate(ex.Message)}");
                        await Task.Delay(TimeSpan.FromSeconds(attempt * 2), ct).ConfigureAwait(false);
                    }
                }

                WriteFallback(kind, payload, last?.Message);
            });
        }

        private async Task WorkerLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                if (_queue.TryDequeue(out Func<CancellationToken, Task>? work))
                {
                    try
                    {
                        await work(ct).ConfigureAwait(false);
                    }
                    catch (Exception ex) when (!ct.IsCancellationRequested)
                    {
                        Debug.Print($"[SkirmishPlay.Stats] Queue worker error: {Truncate(ex.Message)}");
                    }
                }
                else
                {
                    try
                    {
                        await Task.Delay(100, ct).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                }
            }
        }

        private async Task PostAsync(string relativeUrl, string json, string? preferResolution, CancellationToken ct)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, relativeUrl)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };
            if (!string.IsNullOrEmpty(preferResolution))
            {
                request.Headers.TryAddWithoutValidation("Prefer", preferResolution);
            }

            using HttpResponseMessage response = await _http.SendAsync(request, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                throw new InvalidOperationException($"POST {relativeUrl} -> {(int)response.StatusCode}: {Truncate(body)}");
            }
        }

        private async Task PatchAsync(string relativeUrl, string json, CancellationToken ct)
        {
            using var request = new HttpRequestMessage(new HttpMethod("PATCH"), relativeUrl)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };
            request.Headers.TryAddWithoutValidation("Prefer", "return=minimal");

            using HttpResponseMessage response = await _http.SendAsync(request, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                throw new InvalidOperationException($"PATCH {relativeUrl} -> {(int)response.StatusCode}: {Truncate(body)}");
            }
        }

        private void WriteFallback(string kind, object payload, string? error)
        {
            try
            {
                string? dir = Path.GetDirectoryName(_fallbackPath);
                if (!string.IsNullOrEmpty(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                if (File.Exists(_fallbackPath))
                {
                    FileInfo info = new FileInfo(_fallbackPath);
                    if (info.Length > MaxFallbackBytes)
                    {
                        Debug.Print("[SkirmishPlay.Stats] Fallback JSONL is full; dropping payload.");
                        return;
                    }
                }

                var line = new Dictionary<string, object?>
                {
                    ["ts"] = DateTimeOffset.UtcNow.ToString("o"),
                    ["kind"] = kind,
                    ["error"] = Truncate(error),
                    ["payload"] = payload,
                };
                File.AppendAllText(_fallbackPath, JsonSerializer.Serialize(line, JsonOptions) + Environment.NewLine);
                Debug.Print($"[SkirmishPlay.Stats] Wrote fallback JSONL ({kind}) to {_fallbackPath}");
            }
            catch (Exception ex)
            {
                Debug.Print($"[SkirmishPlay.Stats] Fallback write failed: {Truncate(ex.Message)}");
            }
        }

        private static string ResolveFallbackPath()
        {
            string? moduleRoot = null;
            string? dir = Path.GetDirectoryName(typeof(SupabaseStatsClient).Assembly.Location);
            for (int i = 0; i < 5 && !string.IsNullOrEmpty(dir); i++)
            {
                if (File.Exists(Path.Combine(dir, "SubModule.xml")))
                {
                    moduleRoot = dir;
                    break;
                }

                dir = Path.GetDirectoryName(dir);
            }

            return Path.Combine(moduleRoot ?? (Path.GetDirectoryName(typeof(SupabaseStatsClient).Assembly.Location) ?? "."), "stats_fallback.jsonl");
        }

        private static string TrimSlash(string url) => url.TrimEnd('/');

        private static string Truncate(string? text, int max = 240)
        {
            if (string.IsNullOrEmpty(text))
            {
                return string.Empty;
            }

            return text.Length <= max ? text : text.Substring(0, max);
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            try
            {
                _cts.Cancel();
            }
            catch
            {
                // ignore
            }

            // Do not block the mission thread waiting for HTTP. The worker
            // exits on cancel; in-flight requests time out on HttpClient.
            _http.Dispose();
        }
    }

    internal sealed class MatchRow
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; }

        [JsonPropertyName("server_name")]
        public string ServerName { get; set; } = string.Empty;

        [JsonPropertyName("map_id")]
        public string MapId { get; set; } = string.Empty;

        [JsonPropertyName("game_type")]
        public string GameType { get; set; } = "Skirmish";

        [JsonPropertyName("started_at")]
        public DateTimeOffset StartedAt { get; set; }

        [JsonPropertyName("ended_at")]
        public DateTimeOffset? EndedAt { get; set; }

        [JsonPropertyName("rounds_played")]
        public int RoundsPlayed { get; set; }

        [JsonPropertyName("winning_side")]
        public string? WinningSide { get; set; }

        [JsonPropertyName("is_skirmish_club")]
        public bool IsSkirmishClub { get; set; }
    }

    /// <summary>PostgREST RPC body using snake_case parameter names expected by Postgres.</summary>
    internal sealed class RoundPlayerRpcPayload
    {
        public Guid p_match_id { get; set; }
        public int p_round_number { get; set; }
        public string p_steam_id { get; set; } = string.Empty;
        public string p_display_name { get; set; } = string.Empty;
        public string p_team_side { get; set; } = string.Empty;
        public string p_class_group { get; set; } = "Infantry";
        public string p_culture_id { get; set; } = string.Empty;
        public int p_score { get; set; }
        public int p_kills { get; set; }
        public int p_deaths { get; set; }
        public int p_assists { get; set; }
        public bool p_is_mvp { get; set; }
        public bool p_is_winner { get; set; }
        public bool p_first_kill { get; set; }
        public bool p_first_death { get; set; }
        public int p_horse_damage { get; set; }
        public int p_horse_kills { get; set; }
        public int p_kicks { get; set; }
        public int p_couches { get; set; }
        public int p_shots { get; set; }
        public int p_hits { get; set; }
        public int p_headshots { get; set; }
        public int p_teamkills { get; set; }
        public int p_team_hits { get; set; }
        public int p_team_damage { get; set; }
        public int p_melee_damage { get; set; }
        public int p_mounted_damage { get; set; }
        public int p_ranged_damage { get; set; }
        public bool p_is_skirmish_club { get; set; }
        public int p_kills_melee { get; set; }
        public int p_kills_ranged { get; set; }
        public int p_kills_throwing { get; set; }
        public int p_kills_mounted_melee { get; set; }
        public int p_kills_mounted_ranged { get; set; }
        public int p_kills_mounted_throwing { get; set; }
        public int p_deaths_melee { get; set; }
        public int p_deaths_ranged { get; set; }
        public int p_deaths_throwing { get; set; }
        public int p_deaths_mounted_melee { get; set; }
        public int p_deaths_mounted_ranged { get; set; }
        public int p_deaths_mounted_throwing { get; set; }
        public int p_suicides { get; set; }
        public int p_throwing_damage { get; set; }
        public int p_mounted_ranged_damage { get; set; }
        public int p_mounted_throwing_damage { get; set; }
        public int p_throwing_shots { get; set; }
        public int p_throwing_hits { get; set; }
        public int p_throwing_headshots { get; set; }
        public int p_team_hits_received { get; set; }
        public int p_team_damage_received { get; set; }
        public int p_deaths_by_teammate { get; set; }
        public int p_alive_ms { get; set; }
        public int p_spawn_count { get; set; }
    }
}
