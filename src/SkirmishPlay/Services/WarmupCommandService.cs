using System.Reflection;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay.Services
{
    internal static class WarmupCommandService
    {
        private static readonly BindingFlags InstanceFlags =
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

        /// <summary>
        /// Set by !endwarmup so WarmupKeepAliveBehavior allows the Ending countdown.
        /// Cleared by !extendwarmup / keep-alive undo.
        /// </summary>
        internal static bool ManualEndRequested { get; set; }

        public static bool TryExtendWarmup(out string message)
        {
            if (Mission.Current == null)
            {
                message = "No mission is running.";
                return false;
            }

            MissionLobbyComponent? lobby = Mission.Current.GetMissionBehavior<MissionLobbyComponent>();
            if (lobby != null
                && lobby.CurrentMultiplayerState == MissionLobbyComponent.MultiplayerGameState.Ending)
            {
                message = "Cannot extend warmup while the mission is ending.";
                return false;
            }

            MultiplayerWarmupComponent? warmup = Mission.Current.GetMissionBehavior<MultiplayerWarmupComponent>();
            if (warmup == null || !warmup.IsInWarmup)
            {
                message = "Warmup is not active.";
                return false;
            }

            if (!TryGetWarmupState(warmup, out MultiplayerWarmupComponent.WarmupStates state))
            {
                message = "Could not read warmup state.";
                return false;
            }

            // Allow extend anytime during warmup, including the native Ending countdown.
            if (state != MultiplayerWarmupComponent.WarmupStates.InProgress
                && state != MultiplayerWarmupComponent.WarmupStates.Ending
                && state != MultiplayerWarmupComponent.WarmupStates.WaitingForPlayers)
            {
                message = "Warmup is not active.";
                return false;
            }

            MultiplayerTimerComponent? timer = Mission.Current.GetMissionBehavior<MultiplayerTimerComponent>();
            if (timer == null)
            {
                message = "Warmup timer is unavailable.";
                return false;
            }

            ManualEndRequested = false;
            if (!TrySetWarmupState(warmup, MultiplayerWarmupComponent.WarmupStates.InProgress))
            {
                message = "Could not reset warmup state.";
                return false;
            }

            timer.StartTimerAsServer(WarmupKeepAliveBehavior.KeepAliveResetSeconds);
            message = $"Warmup reset to {WarmupKeepAliveBehavior.KeepAliveResetSeconds:0}s.";
            return true;
        }

        public static bool TryEndWarmup(out string message)
        {
            if (Mission.Current == null)
            {
                message = "No mission is running.";
                return false;
            }

            MultiplayerWarmupComponent? warmup = Mission.Current.GetMissionBehavior<MultiplayerWarmupComponent>();
            if (warmup == null || !warmup.IsInWarmup)
            {
                message = "Warmup is not active.";
                return false;
            }

            if (!TryGetWarmupState(warmup, out MultiplayerWarmupComponent.WarmupStates state))
            {
                message = "Could not read warmup state.";
                return false;
            }

            if (state == MultiplayerWarmupComponent.WarmupStates.Ending
                && ManualEndRequested)
            {
                message = "Warmup is already ending (30s countdown).";
                return false;
            }

            if (state != MultiplayerWarmupComponent.WarmupStates.InProgress
                && state != MultiplayerWarmupComponent.WarmupStates.Ending)
            {
                message = "Warmup has not started yet — wait until the warmup timer is running.";
                return false;
            }

            // Allow keep-alive to let this Ending countdown finish.
            ManualEndRequested = true;

            // Same path as CI Server admin EndWarmup / mp_host.end_warmup:
            // public EndWarmupProgress → 30s Ending banner.
            if (state != MultiplayerWarmupComponent.WarmupStates.Ending)
            {
                warmup.EndWarmupProgress();
            }

            MultiplayerTimerComponent? timer = Mission.Current.GetMissionBehavior<MultiplayerTimerComponent>();
            timer?.StartTimerAsServer(30f);

            message = "Warmup is ending (30s countdown).";
            return true;
        }

        private static bool TryGetWarmupState(
            MultiplayerWarmupComponent warmup,
            out MultiplayerWarmupComponent.WarmupStates state)
        {
            state = MultiplayerWarmupComponent.WarmupStates.WaitingForPlayers;
            PropertyInfo? warmupState = typeof(MultiplayerWarmupComponent).GetProperty("WarmupState", InstanceFlags);
            if (warmupState == null)
            {
                return false;
            }

            object? value = warmupState.GetValue(warmup);
            if (value is MultiplayerWarmupComponent.WarmupStates typed)
            {
                state = typed;
                return true;
            }

            return false;
        }

        private static bool TrySetWarmupState(
            MultiplayerWarmupComponent warmup,
            MultiplayerWarmupComponent.WarmupStates state)
        {
            PropertyInfo? warmupState = typeof(MultiplayerWarmupComponent).GetProperty("WarmupState", InstanceFlags);
            MethodInfo? setter = warmupState?.GetSetMethod(nonPublic: true);
            if (setter == null)
            {
                return false;
            }

            setter.Invoke(warmup, new object[] { state });
            return true;
        }
    }
}
