using System;
using SkirmishPlay.Dedicated;
using SkirmishPlay.Services;
using SkirmishPlay.Stats;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay
{
    public sealed class SkirmishPlaySubModule : MBSubModuleBase
    {
        protected override void OnSubModuleLoad()
        {
            base.OnSubModuleLoad();
            SkirmishPlayDedicatedConsoleCommands.Register();
            StatsConfig.Load();
        }

        protected override void OnApplicationTick(float dt)
        {
            base.OnApplicationTick(dt);
            ChatCommandNetworkBridge.Update();
        }

        public override void OnBeforeMissionBehaviorInitialize(Mission mission)
        {
            base.OnBeforeMissionBehaviorInitialize(mission);
            if (!GameNetwork.IsDedicatedServer)
            {
                return;
            }

            if (mission.GetMissionBehavior<WarmupKeepAliveBehavior>() == null)
            {
                mission.AddMissionBehavior(new WarmupKeepAliveBehavior());
                Debug.Print("[SkirmishPlay] WarmupKeepAliveBehavior registered.");
            }

            if (mission.GetMissionBehavior<CommandHelpBroadcastBehavior>() == null)
            {
                mission.AddMissionBehavior(new CommandHelpBroadcastBehavior());
                Debug.Print("[SkirmishPlay] CommandHelpBroadcastBehavior registered.");
            }

            StatsConfig config = StatsConfig.Load();
            if (!config.IsReady)
            {
                return;
            }

            try
            {
                // Flag Domination / Skirmish missions expose MultiplayerRoundController.
                if (mission.GetMissionBehavior<RoundCombatTracker>() == null)
                {
                    mission.AddMissionBehavior(new RoundCombatTracker(config));
                    Debug.Print("[SkirmishPlay.Stats] RoundCombatTracker registered.");
                }
            }
            catch (Exception ex)
            {
                Debug.Print($"[SkirmishPlay.Stats] Failed to register tracker: {ex.Message}");
            }
        }

        public override void OnGameEnd(Game game)
        {
            base.OnGameEnd(game);
            ChatCommandNetworkBridge.Unregister();
        }
    }
}
