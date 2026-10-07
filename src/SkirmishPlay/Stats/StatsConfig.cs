using System;
using System.IO;
using System.Text.Json;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay.Stats
{
    internal sealed class StatsConfig
    {
        private static readonly object Sync = new object();
        private static StatsConfig? _cached;

        public bool Enabled { get; set; }
        public string SupabaseUrl { get; set; } = string.Empty;
        public string ServiceRoleKey { get; set; } = string.Empty;
        public string ServerName { get; set; } = "Skirmish";

        public bool IsReady =>
            Enabled
            && !string.IsNullOrWhiteSpace(ServiceRoleKey)
            && !string.Equals(ServiceRoleKey, "REPLACE_ME", StringComparison.Ordinal)
            && IsHttpsUrl(SupabaseUrl);

        private static bool IsHttpsUrl(string url)
        {
            return Uri.TryCreate(url, UriKind.Absolute, out Uri? uri)
                && uri.Scheme == Uri.UriSchemeHttps;
        }

        public static StatsConfig Load()
        {
            lock (Sync)
            {
                if (_cached != null)
                {
                    return _cached;
                }

                foreach (string path in CandidatePaths())
                {
                    if (!File.Exists(path))
                    {
                        continue;
                    }

                    try
                    {
                        string json = File.ReadAllText(path);
                        StatsConfig? parsed = JsonSerializer.Deserialize<StatsConfig>(json, JsonOptions());
                        if (parsed != null)
                        {
                            _cached = parsed;
                            Debug.Print($"[SkirmishPlay.Stats] Loaded config from {path} (enabled={parsed.Enabled}).");
                            return _cached;
                        }
                    }
                    catch (Exception ex)
                    {
                        Debug.Print($"[SkirmishPlay.Stats] Failed to read {path}: {ex.Message}");
                    }
                }

                _cached = new StatsConfig { Enabled = false };
                Debug.Print("[SkirmishPlay.Stats] No stats_config.json found; stats disabled.");
                return _cached;
            }
        }

        public static void Reload()
        {
            lock (Sync)
            {
                _cached = null;
            }

            Load();
        }

        private static string[] CandidatePaths()
        {
            string? moduleRoot = TryFindModuleRoot();
            string assemblyDir = Path.GetDirectoryName(typeof(StatsConfig).Assembly.Location) ?? ".";
            return new[]
            {
                moduleRoot == null ? string.Empty : Path.Combine(moduleRoot, "stats_config.json"),
                Path.Combine(assemblyDir, "stats_config.json"),
                Path.Combine(Directory.GetCurrentDirectory(), "Modules", "SkirmishPlay", "stats_config.json"),
                Path.Combine(Directory.GetCurrentDirectory(), "stats_config.json"),
            };
        }

        private static string? TryFindModuleRoot()
        {
            string? dir = Path.GetDirectoryName(typeof(StatsConfig).Assembly.Location);
            for (int i = 0; i < 5 && !string.IsNullOrEmpty(dir); i++)
            {
                string subModule = Path.Combine(dir, "SubModule.xml");
                if (File.Exists(subModule))
                {
                    return dir;
                }

                dir = Path.GetDirectoryName(dir);
            }

            return null;
        }

        private static JsonSerializerOptions JsonOptions() => new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };
    }
}
