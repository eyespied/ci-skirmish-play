using System;
using System.Collections.Generic;
using NetworkMessages.FromServer;
using SkirmishPlay.Services;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay
{
    internal sealed class ChatCommandHandler
    {
        public void HandleChatMessage(NetworkCommunicator peer, string message)
        {
            if (string.IsNullOrWhiteSpace(message) || !message.TrimStart().StartsWith("!", StringComparison.Ordinal))
            {
                return;
            }

            string trimmed = message.Trim();
            string[] parts = trimmed.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0)
            {
                return;
            }

            string command = parts[0].ToLowerInvariant();
            switch (command)
            {
                case "!setmap":
                    HandleSetMap(parts);
                    break;
                case "!extendwarmup":
                    HandleExtendWarmup();
                    break;
                case "!endwarmup":
                    HandleEndWarmup();
                    break;
                case "!maps":
                    HandleListMaps();
                    break;
                case "!skirmishclub":
                    HandleSkirmishClub(peer, parts);
                    break;
            }
        }

        private static void HandleSetMap(string[] parts)
        {
            if (parts.Length < 2)
            {
                Reply("Usage: !setmap <map> [culture1 culture2]");
                return;
            }

            string? cultureTeam2 = null;
            string? cultureTeam1 = null;
            string mapQuery;

            if (parts.Length >= 4)
            {
                cultureTeam2 = parts[^1];
                cultureTeam1 = parts[^2];
                mapQuery = string.Join(" ", parts, 1, parts.Length - 3);
            }
            else
            {
                mapQuery = string.Join(" ", parts, 1, parts.Length - 1);
            }

            SetMapResult result = MapCommandService.TrySetMap(mapQuery, cultureTeam1, cultureTeam2);
            Reply(result.AnnouncementMessage ?? result.PlainMessage);
        }

        private static void HandleExtendWarmup()
        {
            if (!WarmupCommandService.TryExtendWarmup(out string result))
            {
                Reply(result);
                return;
            }

            Reply(result);
        }

        private static void HandleEndWarmup()
        {
            if (!WarmupCommandService.TryEndWarmup(out string result))
            {
                Reply(result);
                return;
            }

            Reply(result);
        }

        private static void HandleListMaps()
        {
            if (!MapCommandService.TryListMaps(out IReadOnlyList<string> lines))
            {
                Reply(lines.Count > 0 ? lines[0] : "No maps available.");
                return;
            }

            foreach (string line in lines)
            {
                Reply(line);
            }
        }

        private static void HandleSkirmishClub(NetworkCommunicator peer, string[] parts)
        {
            if (parts.Length < 2)
            {
                Reply($"{SkirmishClubState.StatusMessage} Usage: !skirmishclub start|end|status");
                return;
            }

            string action = parts[1].ToLowerInvariant();
            if (action == "status")
            {
                Reply(SkirmishClubState.StatusMessage);
                return;
            }

            if (action != "start" && action != "end")
            {
                Reply("Usage: !skirmishclub start|end|status");
                return;
            }

            if (peer == null || !peer.IsAdmin)
            {
                Reply("Only admins can start/end Skirmish Club.");
                return;
            }

            bool wantActive = action == "start";
            if (!SkirmishClubState.TrySetActive(wantActive, out string message))
            {
                Reply(message);
                return;
            }

            Reply(message);
        }

        private static void Reply(string text)
        {
            if (string.IsNullOrWhiteSpace(text) || !GameNetwork.IsServer)
            {
                return;
            }

            GameNetwork.BeginBroadcastModuleEvent();
            GameNetwork.WriteMessage(new ServerMessage(text));
            GameNetwork.EndBroadcastModuleEvent(GameNetwork.EventBroadcastFlags.None);
        }
    }
}
