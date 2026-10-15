# NymVPN capability matrix — nym-vpnc + nym-vpnd gRPC (v2026.13.0)

Grounded against tag `nym-vpn-v2026.13.0` (commit `6a8113555d759e1e36e55d0e052b0bf036f37c30`) and the local binary
`~/.cache/yay/nym-vpnd-bin/src/nym-vpn-core-v2026.13.0_linux_x86_64/nym-vpnc` (`nym-vpnc 2026.13.0`).
Repo paths cited per fact. **Major version note:** v2026.13.0 is a full CLI restructure. Legacy commands/flags
(`store-account`, `import-credential`, `list-gateways`, `--entry-gateway-id`, `--mode`, `--disable-killswitch`)
**do not exist** (verified by grep over `nym-vpn-core/crates/nym-vpnc/src`). Config is persisted daemon-side;
the CLI only sends gRPC `Set*` calls.

## 1. nym-vpnc command tree (all verified via `--help`; hidden commands from source)

Global option on every command: `--table-style <psql|ascii|ascii-rounded|modern|sharp|rounded|modern-rounded|extended|markdown|re-structured-text|dots|blank>` (default psql).
**There is NO `--output json` / `-o json`.** Output is human tables/Display strings, except `status -l` config-changed lines (JSON) and `diagnostic` reports (JSON strings).

| Command | Subcommands / flags | Source |
|---|---|---|
| `start-session` | REPL: reads one command per line (shlex-parsed), single authenticated gRPC connection reused | `nym-vpnc/src/commands/session.rs` |
| `exit-session` | ends REPL | same |
| `connect` | `-w, --wait` (block until connected/failed; streams events internally) | `nym-vpnc/src/main.rs:54` |
| `reconnect` | — | main.rs:62 |
| `disconnect` | `-w, --wait` | main.rs:66 |
| `status` | `-l, --listen` (stream state changes until Ctrl-C) | main.rs:72 |
| `info` | daemon version/build/network | main.rs |
| `gateway get` | prints current entry/exit constraints (`Entry point: {:?}` / `Exit point: {:?}`) | `commands/gateway.rs:168` |
| `gateway set` | `--entry-id <base58>` · `--entry-country <ISO3166-1 alpha-2>` · `--entry-random` · `--entry-auto-exclude-jurisdiction on\|off` · `--exit-id <base58>` · `--exit-country <ISO>` · `--exit-region <name>` · `--exit-random` · `--exit-auto-exclude-jurisdiction on\|off` · `--residential-exit on\|off` (at least one flag; partial update OK) | gateway.rs + help |
| `gateway list <mixnet-entry\|mixnet-exit\|wg>` | table: `ID \| Name \| Location \| Performance \| Exit IPv4 \| Exit IPv6 \| Build Version` | gateway.rs:433 |
| `gateway list-filtered <type>` | `--min-score low\|medium\|high\|offline` · `--country <ISO2>` · `--region <name>` · `--residential` · `--quic-enabled` (repeatable AND filters) | help |
| `gateway recents <mixnet\|wg>` | recently connected entry+exit gateways | help |
| `lan get\|set` | `set <allow\|block>` → `SetAllowLan` | commands/lan.rs |
| `ad-block get\|set` (alias `adblock`) | `set <on\|off>` | main.rs:92 |
| `dns get\|enable\|disable\|set [SERVERS]...\|clear\|get-default` | set = space-separated IPs (v4/v6) | commands/dns.rs |
| `tunnel get` | full config dump | commands/tunnel.rs |
| `tunnel set` | **group required, one of:** `--ipv6 on\|off` · `--two-hop on\|off` · `--netstack on\|off` (testing only) · `--circumvention-transports on\|off` (→`SetEnableBridges`) · `--loop-cover-stream-average-delay <ms>` · `--average-packet-delay <ms>` · `--message-sending-delay <ms>` · `--disable-real-traffic-poisson-rate on\|off` · `--geo-location on\|off` · `--gateway-independence on\|off` | tunnel.rs:104 |
| `account get` | identity, canonical identity, mode, controller state | commands/account.rs:75 |
| `account set <MNEMONIC>` | `--location api\|privy\|blockchain` (alias `--mode`); = legacy `store-account` | account.rs:88 |
| `account forget` | wipes account+device+credentials | account.rs:119 |
| `account rotate-keys` | force WG key rotation | account.rs:129 |
| `account links --locale <en-US>` | sign-up/sign-in/account URLs | account.rs:139 |
| `account balance` | on-chain coins | account.rs:150 |
| `account obtain-ticketbooks [--source smartcontract]` (alias `decentralised-obtain-ticketbooks`) | zk-nym/ticketbook top-up for `blockchain` accounts | account.rs:172 |
| `account summary` | traffic used/limit, subscription, status | account.rs:203 |
| `account get-deeplink --kind <KIND> --name <NAME>` · `account store-deeplink --url <nymvpn://...>` | privy deeplink login | account.rs:214 |
| hidden: `account restock-ticketbooks` · `account refresh [--force|-f]` · `account available-tickets` · `account usage` | ticket counts per type, API usage rows | account.rs:33-51 |
| `device get` (default) | device identity (pubkey) | commands/device.rs |
| hidden: `device list [--only-active]` · `device reset [--seed <hex>]` | account devices / reset identity | device.rs:24 |
| `network get\|set <mainnet\|sandbox\|canary>` | network env; **requires daemon restart** | help |
| `sentry get\|set <on\|off>` | error reporting (restart-required, from `GlobalConfig`) | commands/sentry.rs |
| `socks5 enable --socks5-address <host:port> [--rpc-address <host:port>] [--exit-id\|--exit-country\|--exit-region\|--exit-random]` · `disable` · `status` | SOCKS5 + HTTP(S) RPC proxy mode (mixnet only, no system tunnel) | help + `commands/socks5.rs` |
| `geo-exclusion get` · `set enabled <on\|off>` · `set listen-port <port>` · `set excluded-countries CN RU ...` | per-country bypass proxy | commands/geo_exclusion.rs |
| `network-stats get\|set (--enabled on\|off \| --allow-disconnected on\|off)`; hidden `network-stats seed <get|reset>` | anonymous stats | commands/network_stats.rs |
| `diagnostic run [--gateway <id>] [--skip-dns] [--skip-http] [--skip-hybrid-transport]` · `register --gateway <id> [--storage-path <dir>] [--skip-wireguard] [--mixnet] [--lp]` | prints JSON report; register spends an entry ticket | help |
| `favorites get` · `set-entry\|set-exit\|remove-entry\|remove-exit <id\|country\|region>` | **client-side only, no daemon needed** (stored in `~/.local/share/nym-vpn-app/`) | commands/favorites.rs |
| `split-tunnel get` · `add-process <PID>` · `remove-process <PID>` · `clear-processes` · `excluded-processes` | Linux: PID-based exclusion (see also `nym-exclude` helper) | help |
| `profile set <safest\|most-private\|fastest\|random>` | presets: safest=2-hop auto diff-jurisdiction; most-private=5-hop; fastest=2-hop; random=2-hop random | help |
| hidden top-level: `get-config` | full config dump | main.rs:79 |

## 2. Connect / mode / gateway selection

- `connect` takes **only `-w/--wait`** — no mode/gateway flags. Mode is pre-set via `tunnel set --two-hop on|off`
  (off = 5-hop mixnet, on = 2-hop WireGuard) and gateways via `gateway set ...`. This replaces legacy `--mode mixnet|wireguard` + `--entry-gateway-*`/`--exit-gateway-*`.
- `profile set most-private` = 5-hop; `safest|fastest|random` = 2-hop (`nym-vpn-lib/src/service/config/profile.rs`).
- **No killswitch/netfilter flags exist in v2026.13.0** (zero matches for `killswitch` in `nym-vpn-core`). The
  firewall is managed internally by the tunnel state machine (`nym-vpn-lib/src/tunnel_state_machine/mod.rs`,
  `nym-firewall` crate); LAN access is the only user toggle (`lan set allow|block` → `SetAllowLan`).
- DNS: custom DNS only (`dns set`); no per-connect DNS flag. Default DNS queryable via `dns get-default` (`GetDefaultDns`).
- IPv6: `tunnel set --ipv6 off` → `SetDisableIpv6(true)`.

## 3. `status` output

- One-shot: single line `State: <TunnelState Display>`. Formats (`nym-vpn-lib-types/src/tunnel_state.rs:87`):
  `Disconnected` · `Connecting mixnet|wg to <entry_ip> [<gw_id>] → <exit_ip> [<gw_id>], <EstablishState>, try #N` ·
  `Connected mixnet|wg to <entry> [<id>] → <exit> [<id>]` (+ ` via bridge <addr>`) · `Disconnecting [to reconnect|because of an error|because device is offline]` ·
  `Error state: <Reason>` · `Offline[, auto-connect once back online]`.
- State enum (`proto` `TunnelState.oneof`): `disconnected | connecting | connected | disconnecting | error | offline`.
  Error reasons include `SetFirewallPolicy, SetRouting, SetDns, TunDevice, TunnelProvider, Ipv6Unavailable,
  SameEntryAndExitGateway, InvalidEntryGatewayCountry, InvalidExitGatewayCountry, CredentialWastedOn*Gateway,
  BandwidthExceeded, InactiveSubscription, InactiveAccount, MaxDevicesReached, DeviceLoggedOut,
  CredentialFetchingFailed, NoCredentialAvailable, PerformantEntryGatewayUnavailable, PerformantExitGatewayUnavailable,
  InvalidEntryGatewayIdentity, InvalidExitGatewayIdentity, NeedsRelaxedIndependenceCriteria,
  ConnectionAttemptsExceeded, NeedFullDiskPermissions, SplitTunnel, NeedsDeviceLocation, Internal` (proto lines 585-614).
- `-l/--listen`: prints `State: ...` per `NewState`, plus `Configuration changed:\n<pretty JSON>` on
  `ConfigChangedEvent` — the JSON is `VpnServiceConfig` serialized with serde, snake_case keys:
  `entry_point, exit_point, allow_lan, disable_ipv6, enable_two_hop, enable_bridges, enable_ad_blocking,
  enable_conflict_detection, fronting_mode, netstack, min_gateway_vpn_performance, residential_exit,
  enable_custom_dns, custom_dns, mixnet_traffic, network_stats, split_tunnel, geo_exclusion,
  gateway_selection_algorithm_config, gateway_independence` (`nym-vpn-lib-types/src/service.rs:39`).
- **Bandwidth counters are NOT printed by the CLI** — they exist only on the gRPC event stream
  (`MixnetEvent.BandwidthEvent.remaining_bandwidth: int64`; also per-packet `SphinxPacketRates`). For a live
  bandwidth widget the plugin must consume `ListenToEvents` itself.
- No JSON output mode; `nym-vpnd` has `--json-output` but that only formats its own logs (`nym-vpnd/src/cli.rs:29`).

## 4. Gateways / directory

- CLI: `gateway list <mixnet-entry|mixnet-exit|wg>` and `gateway list-filtered` with `--min-score
  (low|medium|high|offline) --country <ISO2> --region --residential --quic-enabled`.
- gRPC: `ListGateways(ListGatewaysRequest{kind: MIXNET_ENTRY|MIXNET_EXIT|WG, user_agent})`,
  `ListFilteredGateways(LookupGatewayFilters{kind, repeated GatewayFilter})` — filter oneof adds `exit`/`vpn`
  filters not exposed by the CLI (`proto` lines 843-858, 1273-1276).
- `GatewayResponse` fields: `id` (base58 identity key), `name`, `location{two_letter_iso_country_code, latitude,
  longitude, city, region, asn{asn,name,kind}}`, `last_probe{last_updated_utc, outcome{as_entry{can_connect,
  can_route}, as_exit{can_connect,can_route_ip_v4,can_route_ip_v6,can_route_ip_external_v4/v6},
  wg{can_register,can_handshake,can_resolve_dns,ping_hosts_performance,ping_ips_performance}, socks5, lp}}`,
  `mixnet_performance` (u32 %), `performance{score, mixnet_score, load, uptime_percentage_last_24_hours}`,
  `exit_ipv4s/exit_ipv6s`, `build_version`, `bridge_params`, `node_family_name`, `lp_details` (proto 393-471).
- **Score enum: OFFLINE|LOW|MEDIUM|HIGH** — no numeric latency/ping column in CLI tables; WG ping floats
  (`ping_hosts_performance`, `ping_ips_performance`) exist only in the probe payload via gRPC.
- Country codes are **two-letter ISO 3166-1 alpha-2** everywhere (`Country.two_letter_iso_country_code`,
  favorites use `celes::Country` alpha2). Regions are free-text strings (e.g. "North America", US state names).
- `gateway recents <mixnet|wg>` → `GetRecentGateways(TunnelType)` returns last entry+exit gateways.
- Entry vs exit filtering is by the `kind` argument (mixnet-entry vs mixnet-exit vs wg lists), not flags.

## 5. Account / credentials

- **Login: `nym-vpnc account set "<12/24-word mnemonic>" [--location api|privy|blockchain]`** (default api).
  This IS the old `store-account` equivalent → gRPC `StoreAccount(StoreAccountRequest{vpn_account_store|
  decentralised_account_store|privy_account_store{mnemonic}})` (proto 862-880). Requires the **daemon running**
  (all commands except `favorites` do — `main.rs` `needs_rpc_client`).
- Legacy `import-credential` is gone: zk-nym ticketbooks/credentials are fetched automatically by the daemon's
  account controller; manual top-up = `account obtain-ticketbooks` (decentralised mode) / hidden
  `account restock-ticketbooks`. Ticket counts: hidden `account available-tickets`.
- `account forget`, `rotate-keys`, `balance` (on-chain), `summary` (traffic/subscription/devices),
  `links --locale`, deeplink login pair (`get-deeplink`/`store-deeplink`), hidden `usage`, `refresh`, `device list`.
- Errors surface as `AccountCommandError` with typed variants (`invalid_mnemonic`, `no_account_stored`,
  `max_device_reached`, `inactive_subscription`, `offline`, `zk_nym_acquisition_failure`, … proto 758-779).

## 6. Daemon gRPC

- **Proto: `nym-vpn-core/crates/nym-vpn-proto/proto/nym_vpn_service.proto`** (single file, package
  `nym_vpn_service`; built in `nym-vpn-proto/build.rs`). Sole service: **`NymVpnService`**.
- **Socket: `/var/run/nym-vpn.sock`** — hardcoded on both sides (`nym-vpnd/src/command_interface.rs:1474-1480`,
  `nym-vpn-proto/src/rpc_client.rs:1057-1063`). Mode 0666, but gated by auth. **No `NYM_VPND_SOCK` env in this
  version** (pre-2026 releases had it). Windows: `\\.\pipe\nym-vpn`; macOS: XPC.
- Service methods (70 RPCs): `Info, GetConfig, SetEntryPoint, SetExitPoint, SetDisableIpv6, SetEnableTwoHop,
  SetEnableBridges, SetEnableAdBlocking, SetEnableConflictDetection, SetNetstack, SetAllowLan, SetResidentialExit,
  SetEnableCustomDns, SetCustomDns, SetMixnetTrafficConfig, SetGeoExclusionEnabled, SetGeoExclusionListenPort,
  SetGeoExclusionExcludedCountries, SetEnableGeoLocation, SetEnableGatewayIndependence,
  SetGatewayIndependenceNotifications, SetFrontingMode, SetNetwork, GetSystemMessages, GetNetworkCompatibility,
  GetFeatureFlags, GetDefaultDns, ConnectTunnel, ReconnectTunnel, DisconnectTunnel, GetTunnelState,
  ListenToEvents(stream), ListGateways, ListFilteredGateways, StoreAccount, AccountBalance,
  DecentralisedObtainTicketbooks, IsAccountStored, ForgetAccount, RotateKeys, GetAccountIdentity,
  GetCanonicalAccountIdentity, GetAccountMode, GetAccountLinks, GetAccountState, RefreshAccountState,
  GetAccountUsage, ResetDeviceIdentity, GetDeviceIdentity, GetDevices, GetActiveDevices, GetAvailableTickets,
  RestockTicketbooks, GetAccountSummary, HandleSubscriptionPayment, GetDeeplink, GetAutologinDeeplink,
  DeeplinkStoreAccount, GetLogPath, DeleteLogFile, IsSentryEnabled, EnableSentry, DisableSentry,
  NetworkStatsSetEnabled, NetworkStatsAllowDisconnected, NetworkStatsResetSeed, NetworkStatsGetSeed,
  EnableSocks5, DisableSocks5, GetSocks5Status, GetPrivyDerivationMessage, RunDiagnostic, RegisterDiagnostic,
  GetTentativeGateways, IsSplitTunnelSupported, GetSplitTunnelExcludedProcesses, SetEnableSplitTunnel,
  AddSplitTunnelApp, RemoveSplitTunnelApp, ClearSplitTunnelApps, AddSplitTunnelProcess,
  RemoveSplitTunnelProcess, ClearSplitTunnelProcesses, NeedFullDiskPermissions, GetRecentGateways, SetProfile`.
- **gRPC-only (no CLI equivalent in v2026.13.0):** `GetSystemMessages`, `GetNetworkCompatibility`,
  `GetFeatureFlags`, `SetGatewayIndependenceNotifications`, `SetFrontingMode`, `SetEnableConflictDetection`,
  `GetTentativeGateways`, `IsSplitTunnelSupported`, `SetEnableSplitTunnel`/`AddSplitTunnelApp`/`RemoveSplitTunnelApp`/
  `ClearSplitTunnelApps` (app-path variant; CLI only has PID variant), `NeedFullDiskPermissions`,
  `HandleSubscriptionPayment`, `GetAutologinDeeplink`, `GetPrivyDerivationMessage`, `GetLogPath`, `DeleteLogFile`,
  `ResetDeviceIdentity` (hidden CLI `device reset` exists), `MinPerformance`-style setters (none; field-only),
  `ListenToEvents` raw stream (CLI only surfaces it via `status -l`), `IsAccountStored` (CLI `account get` surfaces indirectly).

## 7. Events / streaming

- **Yes: `rpc ListenToEvents(Empty) returns (stream TunnelEvent)`** (proto 1270). Event oneof:
  `tunnel_state, mixnet_event (bandwidth!, connection stats, connection events), config_changed_event,
  account_state (LoggedOut|Syncing|ReadyToConnect|Error|Offline|Decentralised|PendingSubscription),
  diagnostics_suggested_event, conflict_detected_event` (proto 655-686, 803-836).
- The official Tauri app uses this stream for live updates; `nym-vpnc status --listen` uses it too but prints
  only state + config lines (bandwidth events are swallowed — `main.rs:330`). `connect -w`/`disconnect -w` also
  consume it. A QML plugin should hold its own `ListenToEvents` stream (tonic/grpcurl over the unix socket) or
  poll `GetTunnelState`.

## 8. Version/env/config quirks for shell/QML wrapping

- **Auth (Linux):** every new client connection triggers a daemon auth query. Accepted if the peer's UID is in
  the **`nym-vpn` UNIX group** (sysusers: `nym-vpn-core/crates/nym-vpnd/.pkg/sysusers.d/nym-vpn.conf`), else a
  **polkit prompt** `com.nymvpn.vpnd.unix-access` fires (active session: `auth_self`; policy auto-installed to
  `/usr/share/polkit-1/actions` or `/etc/polkit-1/actions`; 60 s interaction timeout)
  (`nym-ipc/src/authentication/linux.rs:23-50`, `.pkg/com.nymvpn.vpnd.unix-access.policy`). Observed on this box:
  CLI calls hang silently when the user is not in the group and no polkit agent answers. **Plugin box must add the
  user to `nym-vpn` group**, else every bar click pops an auth dialog (or blocks 60 s).
- Daemon env vars (`nym-vpn-lib/src/paths.rs:16-25`): `NYM_VPND_DATA_DIR` (default `/var/lib/nym-vpnd`),
  `NYM_VPND_CONFIG_DIR` (default `/etc/nym`), `NYM_VPND_LOG_DIR` (default `/var/log/nym-vpnd`).
  Network env cached under `<config_dir>` (`NetworkCache`); `NYM_VPN_API` is *exported* by network setup, not read.
  `nym-vpn-lib/src/service/socks5/config.rs`: `NYM_VPND_SOCKS5_REQUEST_TIMEOUT_SECS`, `NYM_VPND_SOCKS5_IDLE_TIMEOUT_SECS`.
  `nym-vpn-app` honors `NYM_VPN_SYSTEMD_OVERRIDE_FILE`. **No `NYM_VPN_*` env is read by `nym-vpnc` itself** except
  XDG defaults for favorites storage (`dirs::data_dir()/nym-vpn-app`, i.e. `~/.local/share/nym-vpn-app`).
- Global daemon config: `<config_dir>/config.toml` (`GlobalConfig{network_name, sentry_monitoring}`,
  `nym-vpn-lib/src/config.rs:44`); service config persisted by daemon (`ServiceConfigStorageType::Persistent`,
  data dir). `network set` requires daemon restart to take effect.
- Logs: `/var/log/nym-vpnd/nym-vpnd.log` (+ auto-rotated `nym-vpnd.old.log`)
  (`nym-vpn-lib/src/logging.rs:31-40`); standalone runs log to stdout only. `GetLogPath`/`DeleteLogFile` RPCs exist.
- systemd unit runs `/usr/bin/nym-vpnd -v run-as-service` (`nym-vpnd/.pkg/aur/nym-vpnd.service`).
- Daemon CLI: `nym-vpnd [-v...] [--user-agent <str>] [--json-output] [run-as-service|run-with-args
  [--disable-client-verification]]` (`nym-vpnd/src/cli.rs`). `--disable-client-verification` skips auth (debug).
- `ConnectTunnel` returns just `BoolValue` — success of the *attempt*, not the connection; real result arrives as events.
- `gateway list` output can be large (hundreds of rows); use `list-filtered`/`--table-style markdown` if parsing.
- All CLI state mutations are async daemon-side with no ACK payload (Empty) — re-read `get-config`/`status` after set.
