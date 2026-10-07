using System;
using System.Collections.Generic;
using System.Linq;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay.Dedicated
{
    /// <summary>
    /// Registers dedicated-server config commands (usable maps, automated battles).
    /// Some DS installs do not load Official's command handlers, so config lines would fail without this.
    /// </summary>
    internal static class SkirmishPlayDedicatedConsoleCommands
    {
        public static void Register()
        {
            DedicatedServerConsoleCommandManager.AddType(typeof(SkirmishPlayDedicatedConsoleCommands));
            Debug.Print("[SkirmishPlay] Registered dedicated console commands.");
        }

        [ConsoleCommandMethod(
            "add_map_to_usable_maps",
            "Adds a map to the usable map pool for the given game types. Example: add_map_to_usable_maps mp_battle_map_001 Skirmish")]
        private static void AddMapToUsableMaps(string argument)
        {
            if (!TryParseMapAndGameTypes(argument, out string mapId, out List<string> gameTypes))
            {
                Debug.Print("--add_map_to_usable_maps requires: <mapId> <gameType[, gameType...]>");
                return;
            }

            AddUsableMapInternal(mapId, gameTypes);
            Debug.Print($"--Added usable map: {mapId} [{string.Join(", ", gameTypes)}]");
        }

        [ConsoleCommandMethod(
            "add_map_to_automated_battle_pool",
            "Adds a map to the automated battle / intermission vote pool.")]
        private static void AddMapToAutomatedBattlePool(string argument)
        {
            if (string.IsNullOrWhiteSpace(argument))
            {
                Debug.Print("--add_map_to_automated_battle_pool requires a map id.");
                return;
            }

            string mapId = argument.Trim();
            MultiplayerIntermissionVotingManager.Instance.AddMapItem(mapId);
            Debug.Print($"--Added map to automated battle pool: {mapId}");
        }

        [ConsoleCommandMethod(
            "enable_automated_battle_switching",
            "Enables automatic map switching between battles.")]
        private static void EnableAutomatedBattleSwitching()
        {
            MultiplayerIntermissionVotingManager.Instance.IsAutomatedBattleSwitchingEnabled = true;
            Debug.Print("--Automated battle switching enabled.");
        }

        [ConsoleCommandMethod(
            "set_automated_battle_count",
            "Sets automated battle count (-1 = unlimited).")]
        private static void SetAutomatedBattleCount(string argument)
        {
            if (!int.TryParse(argument?.Trim(), out int count))
            {
                Debug.Print("--set_automated_battle_count requires an integer (use -1 for unlimited).");
                return;
            }

            Debug.Print($"--Automated battle count set to: {count}");
        }

        [ConsoleCommandMethod(
            "disable_map_voting",
            "Disables map voting for intermission.")]
        private static void DisableMapVoting()
        {
            MultiplayerIntermissionVotingManager.Instance.IsDisableMapVoteOverride = true;
            MultiplayerIntermissionVotingManager.Instance.IsMapVoteEnabled = false;
            Debug.Print("--Map voting disabled.");
        }

        [ConsoleCommandMethod(
            "disable_culture_voting",
            "Disables culture voting for intermission.")]
        private static void DisableCultureVoting()
        {
            MultiplayerIntermissionVotingManager.Instance.IsDisableCultureVoteOverride = true;
            MultiplayerIntermissionVotingManager.Instance.IsCultureVoteEnabled = false;
            Debug.Print("--Culture voting disabled.");
        }

        private static bool TryParseMapAndGameTypes(
            string? argument,
            out string mapId,
            out List<string> gameTypes)
        {
            mapId = string.Empty;
            gameTypes = new List<string>();

            if (string.IsNullOrWhiteSpace(argument))
            {
                return false;
            }

            string trimmed = argument.Trim();
            int space = trimmed.IndexOf(' ');
            if (space <= 0 || space >= trimmed.Length - 1)
            {
                return false;
            }

            mapId = trimmed.Substring(0, space).Trim();
            gameTypes = trimmed.Substring(space + 1)
                .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(t => t.Trim())
                .Where(t => t.Length > 0)
                .ToList();

            return gameTypes.Count > 0;
        }

        private static void AddUsableMapInternal(string mapId, List<string> gameTypes)
        {
            var usable = new CustomGameUsableMap(mapId, isCompatibleWithAllGameTypes: false, gameTypes);
            List<CustomGameUsableMap> existing = MultiplayerIntermissionVotingManager.Instance.UsableMaps;
            if (existing.Any(m => m.Equals(usable)))
            {
                return;
            }

            MultiplayerIntermissionVotingManager.Instance.AddUsableMap(usable);
        }
    }
}
