using System.Reflection;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay.Services
{
    /// <summary>
    /// Keeps warmup running until an admin uses !endwarmup.
    /// When under 1 minute remains, resets the timer to 5 minutes.
    /// Also undoes native auto-end (timer &lt;= 30s or lobby-full CheckForWarmupEnd).
    /// Must not touch the shared mission timer while the lobby is Ending —
    /// that timer drives post-match map rotation.
    /// </summary>
    internal sealed class WarmupKeepAliveBehavior : MissionBehavior
    {
        public override MissionBehaviorType BehaviorType => MissionBehaviorType.Other;

        public const float KeepAliveThresholdSeconds = 60f;
        public const float KeepAliveResetSeconds = 300f;

        private static readonly BindingFlags InstanceFlags =
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

        private MultiplayerWarmupComponent? _warmup;
        private MultiplayerTimerComponent? _timer;
        private MissionLobbyComponent? _lobby;
        private float _lastUndoLogTime = -999f;

        public override void AfterStart()
        {
            base.AfterStart();
            if (!GameNetwork.IsDedicatedServer)
            {
                return;
            }

            _warmup = Mission.GetMissionBehavior<MultiplayerWarmupComponent>();
            _timer = Mission.GetMissionBehavior<MultiplayerTimerComponent>();
            _lobby = Mission.GetMissionBehavior<MissionLobbyComponent>();
            WarmupCommandService.ManualEndRequested = false;
            Debug.Print("[SkirmishPlay] Warmup keep-alive active (auto-end blocked; bump at 60s → 300s).");
        }

        public override void OnPreDisplayMissionTick(float dt)
        {
            base.OnPreDisplayMissionTick(dt);
            // Same tick phase as MultiplayerWarmupComponent — undo auto-end ASAP.
            TickKeepAlive();
        }

        public override void OnMissionTick(float dt)
        {
            base.OnMissionTick(dt);
            TickKeepAlive();
        }

        private void TickKeepAlive()
        {
            if (!GameNetwork.IsDedicatedServer || _warmup == null || _timer == null)
            {
                return;
            }

            // Warmup itself runs while lobby is WaitingFirstPlayers.
            // Playing starts only AFTER warmup ends. Lobby Ending = map rotation.
            if (!IsSafeToTouchWarmupTimer())
            {
                return;
            }

            if (!_warmup.IsInWarmup)
            {
                return;
            }

            if (!TryGetWarmupState(_warmup, out MultiplayerWarmupComponent.WarmupStates state))
            {
                return;
            }

            if (state == MultiplayerWarmupComponent.WarmupStates.Ending)
            {
                if (WarmupCommandService.ManualEndRequested)
                {
                    return;
                }

                UndoAutoEnd();
                return;
            }

            if (state != MultiplayerWarmupComponent.WarmupStates.InProgress)
            {
                return;
            }

            float remaining = _timer.GetRemainingTime(isSynched: false);
            if (remaining > KeepAliveThresholdSeconds)
            {
                return;
            }

            _timer.StartTimerAsServer(KeepAliveResetSeconds);
            Debug.Print($"[SkirmishPlay] Warmup keep-alive: {remaining:0}s left → reset to {KeepAliveResetSeconds:0}s.");
        }

        private bool IsSafeToTouchWarmupTimer()
        {
            if (_lobby == null)
            {
                _lobby = Mission.GetMissionBehavior<MissionLobbyComponent>();
            }

            if (_lobby == null)
            {
                return false;
            }

            // Never touch the timer during post-match Ending (map change).
            if (_lobby.CurrentMultiplayerState == MissionLobbyComponent.MultiplayerGameState.Ending)
            {
                return false;
            }

            if (Mission.CurrentState != Mission.State.Continuing)
            {
                return false;
            }

            return true;
        }

        private void UndoAutoEnd()
        {
            if (!IsSafeToTouchWarmupTimer())
            {
                return;
            }

            if (!TrySetWarmupState(_warmup!, MultiplayerWarmupComponent.WarmupStates.InProgress))
            {
                return;
            }

            _timer!.StartTimerAsServer(KeepAliveResetSeconds);

            float now = Mission.CurrentTime;
            if (now - _lastUndoLogTime >= 10f)
            {
                _lastUndoLogTime = now;
                Debug.Print("[SkirmishPlay] Blocked auto warmup end — use !endwarmup to finish warmup.");
            }
        }

        private static bool TryGetWarmupState(
            MultiplayerWarmupComponent warmup,
            out MultiplayerWarmupComponent.WarmupStates state)
        {
            state = MultiplayerWarmupComponent.WarmupStates.WaitingForPlayers;
            PropertyInfo? prop = typeof(MultiplayerWarmupComponent).GetProperty("WarmupState", InstanceFlags);
            object? value = prop?.GetValue(warmup);
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
            PropertyInfo? prop = typeof(MultiplayerWarmupComponent).GetProperty("WarmupState", InstanceFlags);
            MethodInfo? setter = prop?.GetSetMethod(nonPublic: true);
            if (setter == null)
            {
                return false;
            }

            setter.Invoke(warmup, new object[] { state });
            return true;
        }
    }
}
