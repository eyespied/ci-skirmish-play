using NetworkMessages.FromServer;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay.Services
{
    /// <summary>
    /// Periodically reminds players of the available chat commands.
    /// </summary>
    internal sealed class CommandHelpBroadcastBehavior : MissionBehavior
    {
        public override MissionBehaviorType BehaviorType => MissionBehaviorType.Other;

        private const float CommandsIntervalSeconds = 300f;
        private const float CommandsFirstDelaySeconds = 45f;

        private float _commandsElapsed;
        private bool _sentFirstCommands;

        public override void AfterStart()
        {
            base.AfterStart();
            _commandsElapsed = 0f;
            _sentFirstCommands = false;
            if (GameNetwork.IsDedicatedServer)
            {
                Debug.Print("[SkirmishPlay] Chat command broadcasts active (5m).");
            }
        }

        public override void OnMissionTick(float dt)
        {
            base.OnMissionTick(dt);
            if (!GameNetwork.IsDedicatedServer || !GameNetwork.IsServer)
            {
                return;
            }

            TickCommands(dt);
        }

        private void TickCommands(float dt)
        {
            _commandsElapsed += dt;
            float due = _sentFirstCommands ? CommandsIntervalSeconds : CommandsFirstDelaySeconds;
            if (_commandsElapsed < due)
            {
                return;
            }

            _commandsElapsed = 0f;
            _sentFirstCommands = true;
            Broadcast("Commands: !maps | !setmap <map> [c1 c2] | !extendwarmup | !endwarmup");
            Broadcast("Skirmish Club (admin): !skirmishclub start | end | status");
        }

        private static void Broadcast(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return;
            }

            GameNetwork.BeginBroadcastModuleEvent();
            GameNetwork.WriteMessage(new ServerMessage(text));
            GameNetwork.EndBroadcastModuleEvent(GameNetwork.EventBroadcastFlags.None);
        }
    }
}
