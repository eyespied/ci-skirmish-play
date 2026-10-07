# Skirmish Play

Server-only Bannerlord module for Native Skirmish map commands, controlled warmup and optional live-round statistics. Ordinary players do not install it. It depends on Native and Multiplayer, with internal module ID `SkirmishPlay`.

## Commands

| Command | Effect |
|---|---|
| `!setmap <scene> [culture1 culture2]` | Select a registered scene/factions for the next mission transition. |
| `!maps` | List configured usable maps. |
| `!extendwarmup` | Reset the warmup timer to five minutes. |
| `!endwarmup` | Begin the 30-second warmup-end countdown. |
| `!skirmishclub status` | Show club tagging state. |
| `!skirmishclub start/end` | Admin-only control of upcoming live-round club tagging. |

Warmup does not auto-end; the keep-alive extends it until explicitly ended. Help is broadcast after mission start and periodically. Map IDs must match registered scenes, not display labels.

## Build and install

Requires the .NET SDK and your own Bannerlord dedicated-server reference assemblies. Current source was compiled against installed v1.4.8-compatible assemblies; check your game's version before reusing them.

```powershell
dotnet build .\SkirmishPlay.sln -c Release -p:BannerlordPath="D:\Games\Bannerlord"
```

The build stages `dist/SubModule.xml` and the module's Windows/Linux DLLs. Copy the generated dist content to `<DedicatedServer>/Modules/SkirmishPlay`, enable `_MODULES_*Native*Multiplayer*SkirmishPlay*_MODULES_` and restart your server. Do not distribute the game's reference DLLs.

`server_config.example.txt` is a minimal Native example. Add your own maps, passwords and game options locally. The module registers usable/automated map-pool controls, battle switching/count, and map/culture voting switches. Private host addresses, deployment scripts, live configs and game files are not part of this public repository.

## Optional statistics

Statistics are disabled by default; no database URL/key is built into this public source. To enable them for your own installation, apply the SQL migrations under `supabase/migrations/` in order to **your own** database, then copy `stats_config.example.json` to ignored `stats_config.json` beside the module manifest. Set `enabled`, your HTTPS `supabaseUrl`, private `serviceRoleKey` and a server label. Never commit that real config or expose the backend key to clients.

Only completed live rounds are submitted; warmup is excluded. Club tagging routes tagged rounds separately from ordinary career stats. Upload/network behavior requires a real finished round and database verification. The module remains useful without any database configuration.

## Source and validation

`src/SkirmishPlay` holds chat, map/warmup and statistics services; `module/SubModule.xml` is the package manifest; `Directory.Build.props` defines overridable build defaults. Source-only GitHub snapshot: build outputs are local. No CI production config, domain, server identity or credentials are included. Compilation is separate from live multiplayer testing; verify commands, rotation, warmup and optional upload on a test server before release.
