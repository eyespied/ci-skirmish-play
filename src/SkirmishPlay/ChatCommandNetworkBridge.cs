using NetworkMessages.FromClient;
using TaleWorlds.Core;
using TaleWorlds.Library;
using TaleWorlds.MountAndBlade;

namespace SkirmishPlay
{
    /// <summary>
    /// Hooks player chat at the network layer so commands work on dedicated servers even when
    /// ChatBox is recreated between lobby/mission/intermission.
    /// </summary>
    internal static class ChatCommandNetworkBridge
    {
        private static ChatCommandHandler? _handler;
        private static bool _networkHandlersRegistered;

        public static void Update()
        {
            if (!GameNetwork.IsDedicatedServer || _networkHandlersRegistered || !GameNetwork.IsServer)
            {
                return;
            }

            _handler ??= new ChatCommandHandler();

            var registerer = new GameNetwork.NetworkMessageHandlerRegisterer(
                GameNetwork.NetworkMessageHandlerRegisterer.RegisterMode.Add);
            registerer.Register<PlayerMessageAll>(HandlePlayerMessageAll);
            registerer.Register<PlayerMessageTeam>(HandlePlayerMessageTeam);
            _networkHandlersRegistered = true;
            Debug.Print("[SkirmishPlay] Chat command network handlers registered.");
        }

        public static void Unregister()
        {
            if (!_networkHandlersRegistered)
            {
                return;
            }

            var registerer = new GameNetwork.NetworkMessageHandlerRegisterer(
                GameNetwork.NetworkMessageHandlerRegisterer.RegisterMode.Remove);
            registerer.Register<PlayerMessageAll>(HandlePlayerMessageAll);
            registerer.Register<PlayerMessageTeam>(HandlePlayerMessageTeam);
            _networkHandlersRegistered = false;
        }

        private static bool HandlePlayerMessageAll(NetworkCommunicator peer, PlayerMessageAll message)
        {
            _handler?.HandleChatMessage(peer, message.Message);
            return true;
        }

        private static bool HandlePlayerMessageTeam(NetworkCommunicator peer, PlayerMessageTeam message)
        {
            _handler?.HandleChatMessage(peer, message.Message);
            return true;
        }
    }
}
