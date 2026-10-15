# Nym VPN for Omarchy

A theme-native Omarchy bar widget and route panel for the NymVPN daemon. It uses the active Omarchy theme and does not include account credentials.

The bar chip reads `NYM` and opens the route panel:

- **Route map** — a flat equirectangular map using Natural Earth 1:110m outlines and gateway locations from Nym's public directory. It draws **YOU → ENTRY → EXIT**; ANON · 5-HOP mode shows approximate intermediate relay positions because Nym selects those relays per connection.
- **Route cards and locations** — entry/exit country and city, with searchable country selectors.
- **Connection controls** — FAST · 2-HOP (WireGuard) or ANON · 5-HOP (mixnet), Connect / Reconnect, Disconnect, and Open app.
- **Traffic stats** — interface rates, totals, and gateway ping while connected.

The location shown as **YOU** is best-effort: the helper queries Nym's public geo-IP endpoint when disconnected, then falls back to cached location or timezone data. While connected, it uses cached location rather than reporting the VPN exit as your position.

## Privacy

When the tunnel is down, the widget's 30-second status poll calls `https://nymvpn.com/api/public/v1/geo/ip`; that service receives the client's public IP. The returned IP and location are cached locally at `~/.cache/omarchy/nym-geo.json`. While connected, the helper does not call that geo-IP endpoint. The gateway directory is fetched from Nym's public API and cached for up to six hours. No runtime cache, account credentials, or user-specific route data is included in this repository.

## Requirements

- Omarchy with its Quickshell plugin support.
- NymVPN daemon installed and available as `nym-vpnd.service`.
- The bundled `bin/nym-vpnc` is the upstream NymVPN CLI v2026.12.4 for x86_64 GNU/Linux. Its separate GPL-3.0-only license and corresponding source are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Install into Omarchy

```bash
omarchy plugin enable master.nym-vpn
omarchy bar put master.nym-vpn --section right
```

Keys in the panel: `C` connect, `D` disconnect, `R` refresh, `O` open app. Daemon actions run only after an explicit user action, never from the status timer.

## Licensing

The plugin's original source is MIT-licensed; see [LICENSE](LICENSE). The bundled NymVPN CLI and Natural Earth datasets have separate third-party terms described in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
