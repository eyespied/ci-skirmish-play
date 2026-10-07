using System;
using System.Collections.Generic;
using System.Linq;
using TaleWorlds.Core;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.Multiplayer;

namespace SkirmishPlay.Services
{
    internal sealed class SetMapResult
    {
        public bool Success { get; init; }
        public string PlainMessage { get; init; } = string.Empty;
        public string? AnnouncementMessage { get; init; }
    }

    internal static class MapCommandService
    {
        private const int MaxChatLineLength = 220;

        public static bool TryListMaps(out IReadOnlyList<string> lines)
        {
            lines = Array.Empty<string>();

            string gameType = MultiplayerOptions.OptionType.GameType.GetStrValue();
            if (string.IsNullOrWhiteSpace(gameType))
            {
                lines = new[] { "Game type is not configured." };
                return false;
            }

            IReadOnlyList<string> usableMaps = MultiplayerIntermissionVotingManager.Instance.GetUsableMaps(gameType);
            if (usableMaps == null || usableMaps.Count == 0)
            {
                lines = new[]
                {
                    $"No usable maps configured for {gameType}. Add maps with add_map_to_usable_maps in your server config."
                };
                return false;
            }

            lines = BuildMapListLines(gameType, usableMaps);
            return true;
        }

        public static SetMapResult TrySetMap(string mapQuery, string? cultureTeam1Query, string? cultureTeam2Query)
        {
            if (string.IsNullOrWhiteSpace(mapQuery))
            {
                return Fail("Map name is required.");
            }

            bool wantsCultures = !string.IsNullOrWhiteSpace(cultureTeam1Query) ||
                                 !string.IsNullOrWhiteSpace(cultureTeam2Query);
            if (wantsCultures &&
                (string.IsNullOrWhiteSpace(cultureTeam1Query) || string.IsNullOrWhiteSpace(cultureTeam2Query)))
            {
                return Fail("Usage: !setmap <map> <culture1> <culture2>");
            }

            string gameType = MultiplayerOptions.OptionType.GameType.GetStrValue();
            if (string.IsNullOrWhiteSpace(gameType))
            {
                return Fail("Game type is not configured.");
            }

            IReadOnlyList<string> usableMaps = MultiplayerIntermissionVotingManager.Instance.GetUsableMaps(gameType);
            if (usableMaps == null || usableMaps.Count == 0)
            {
                return Fail(
                    $"No usable maps configured for {gameType}. Add maps with add_map_to_usable_maps in your server config.");
            }

            string? mapId = ResolveMapId(mapQuery.Trim(), usableMaps);
            if (mapId == null)
            {
                return Fail(BuildUnknownMapMessage(mapQuery, usableMaps));
            }

            BasicCultureObject? cultureTeam1 = null;
            BasicCultureObject? cultureTeam2 = null;
            if (wantsCultures)
            {
                if (!CultureCommandService.TryResolveCulture(cultureTeam1Query!, out cultureTeam1, out string cultureError))
                {
                    return Fail(cultureError);
                }

                if (!CultureCommandService.TryResolveCulture(cultureTeam2Query!, out cultureTeam2, out cultureError))
                {
                    return Fail(cultureError);
                }
            }

            MultiplayerOptions.OptionType.Map.SetValue(mapId, MultiplayerOptions.MultiplayerOptionsAccessMode.NextMapOptions);
            MultiplayerIntermissionVotingManager.Instance.IsMapVoteEnabled = false;
            MultiplayerIntermissionVotingManager.Instance.IsMapSelectedByAdmin = true;

            if (cultureTeam1 != null && cultureTeam2 != null)
            {
                MultiplayerOptions.OptionType.CultureTeam1.SetValue(
                    cultureTeam1.StringId,
                    MultiplayerOptions.MultiplayerOptionsAccessMode.NextMapOptions);
                MultiplayerOptions.OptionType.CultureTeam2.SetValue(
                    cultureTeam2.StringId,
                    MultiplayerOptions.MultiplayerOptionsAccessMode.NextMapOptions);
                MultiplayerIntermissionVotingManager.Instance.IsCultureVoteEnabled = false;
            }

            string announcement = ChatAnnouncementService.BuildSetMapAnnouncement(mapId, cultureTeam1, cultureTeam2);

            MultiplayerAdminComponent? admin = Mission.Current?.GetMissionBehavior<MultiplayerAdminComponent>();
            if (admin != null)
            {
                admin.AdminEndMission();
                return new SetMapResult
                {
                    Success = true,
                    PlainMessage = announcement,
                    AnnouncementMessage = announcement
                };
            }

            MultiplayerOptions.OptionType.Map.SetValue(mapId, MultiplayerOptions.MultiplayerOptionsAccessMode.CurrentMapOptions);
            if (cultureTeam1 != null && cultureTeam2 != null)
            {
                MultiplayerOptions.OptionType.CultureTeam1.SetValue(
                    cultureTeam1.StringId,
                    MultiplayerOptions.MultiplayerOptionsAccessMode.CurrentMapOptions);
                MultiplayerOptions.OptionType.CultureTeam2.SetValue(
                    cultureTeam2.StringId,
                    MultiplayerOptions.MultiplayerOptionsAccessMode.CurrentMapOptions);
            }

            return new SetMapResult
            {
                Success = true,
                PlainMessage = $"Next map set to {mapId}.",
                AnnouncementMessage = announcement
            };
        }

        private static SetMapResult Fail(string message)
        {
            return new SetMapResult { Success = false, PlainMessage = message };
        }

        private static string? ResolveMapId(string mapQuery, IReadOnlyList<string> usableMaps)
        {
            string? exact = usableMaps.FirstOrDefault(
                map => string.Equals(map, mapQuery, StringComparison.OrdinalIgnoreCase));
            if (exact != null)
            {
                return exact;
            }

            List<string> partialMatches = usableMaps
                .Where(map => map.Contains(mapQuery, StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (partialMatches.Count == 1)
            {
                return partialMatches[0];
            }

            return null;
        }

        private static string BuildUnknownMapMessage(string mapQuery, IReadOnlyList<string> usableMaps)
        {
            List<string> partialMatches = usableMaps
                .Where(map => map.Contains(mapQuery, StringComparison.OrdinalIgnoreCase))
                .Take(5)
                .ToList();

            if (partialMatches.Count > 1)
            {
                return $"Multiple maps match '{mapQuery}': {string.Join(", ", partialMatches)}";
            }

            int previewCount = Math.Min(usableMaps.Count, 8);
            string preview = string.Join(", ", usableMaps.Take(previewCount));
            if (usableMaps.Count > previewCount)
            {
                preview += $", ... ({usableMaps.Count} total)";
            }

            return $"Unknown map '{mapQuery}'. Usable maps: {preview}";
        }

        private static IReadOnlyList<string> BuildMapListLines(string gameType, IReadOnlyList<string> usableMaps)
        {
            var lines = new List<string> { $"Usable maps for {gameType} ({usableMaps.Count}):" };
            string currentLine = string.Empty;

            foreach (string map in usableMaps.OrderBy(map => map, StringComparer.OrdinalIgnoreCase))
            {
                string entry = currentLine.Length == 0 ? map : currentLine + ", " + map;
                if (entry.Length > MaxChatLineLength && currentLine.Length > 0)
                {
                    lines.Add(currentLine);
                    currentLine = map;
                }
                else
                {
                    currentLine = entry;
                }
            }

            if (currentLine.Length > 0)
            {
                lines.Add(currentLine);
            }

            return lines;
        }
    }
}
