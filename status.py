#!/usr/bin/env python3
"""Nym bar helper. The timer path never opens the daemon socket."""

import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CLIENT = ROOT / "bin" / "nym-vpnc"
CACHE = Path.home() / ".cache" / "omarchy"
CATALOG_PATH = CACHE / "nym-countries.json"
ROUTE_PATH = CACHE / "nym-route.json"
GEO_PATH = CACHE / "nym-geo.json"
API = "https://nymvpn.com/api/public/v1/directory/gateways?show_vpn_only=true"
GEO_API = "https://nymvpn.com/api/public/v1/geo/ip"
CODE = re.compile(r"^[A-Z]{2}$")
HOP = re.compile(r"([0-9A-Za-z.:]+):(\d+)\s+\[([A-Za-z0-9]+)\]")
ARROW = re.compile(r"\s+(?:→|->)\s+")

NAMES = {
    "AE": "United Arab Emirates", "AL": "Albania", "AM": "Armenia", "AR": "Argentina",
    "AT": "Austria", "AU": "Australia", "AZ": "Azerbaijan", "BA": "Bosnia",
    "BE": "Belgium", "BG": "Bulgaria", "BO": "Bolivia", "BR": "Brazil",
    "CA": "Canada", "CH": "Switzerland", "CL": "Chile", "CO": "Colombia",
    "CR": "Costa Rica", "CY": "Cyprus", "CZ": "Czechia", "DE": "Germany",
    "DK": "Denmark", "EC": "Ecuador", "EE": "Estonia", "ES": "Spain",
    "FI": "Finland", "FR": "France", "GB": "United Kingdom", "GE": "Georgia",
    "GR": "Greece", "HK": "Hong Kong", "HR": "Croatia", "HU": "Hungary",
    "ID": "Indonesia", "IE": "Ireland", "IL": "Israel", "IN": "India",
    "IS": "Iceland", "IT": "Italy", "JP": "Japan", "KH": "Cambodia",
    "KR": "South Korea", "LT": "Lithuania", "LU": "Luxembourg", "LV": "Latvia",
    "MD": "Moldova", "MX": "Mexico", "MY": "Malaysia", "NL": "Netherlands",
    "NO": "Norway", "NZ": "New Zealand", "PA": "Panama", "PL": "Poland",
    "PT": "Portugal", "RO": "Romania", "RS": "Serbia", "SE": "Sweden",
    "SG": "Singapore", "SI": "Slovenia", "SK": "Slovakia", "TH": "Thailand",
    "TR": "Turkey", "TW": "Taiwan", "UA": "Ukraine", "US": "United States",
    "ZA": "South Africa",
}


def run(args, timeout=12, text_in=None):
    try:
        done = subprocess.run(
            args,
            text=True,
            capture_output=True,
            input=text_in,
            stdin=None if text_in is not None else subprocess.DEVNULL,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return 1, "", str(error)
    return done.returncode, done.stdout or "", done.stderr or ""


def load_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return fallback


def save_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=True) + "\n")


TZ_COORDS = {
    "Europe/Copenhagen": (55.6761, 12.5683, "Copenhagen", "DK"),
    "Europe/Stockholm": (59.3293, 18.0686, "Stockholm", "SE"),
    "Europe/Oslo": (59.9139, 10.7522, "Oslo", "NO"),
    "Europe/Berlin": (52.52, 13.405, "Berlin", "DE"),
    "Europe/London": (51.5074, -0.1278, "London", "GB"),
    "Europe/Paris": (48.8566, 2.3522, "Paris", "FR"),
    "Europe/Amsterdam": (52.3676, 4.9041, "Amsterdam", "NL"),
    "Europe/Madrid": (40.4168, -3.7038, "Madrid", "ES"),
    "Europe/Rome": (41.9028, 12.4964, "Rome", "IT"),
    "Europe/Warsaw": (52.2297, 21.0122, "Warsaw", "PL"),
    "Europe/Helsinki": (60.1699, 24.9384, "Helsinki", "FI"),
    "America/New_York": (40.7128, -74.006, "New York", "US"),
    "America/Chicago": (41.8781, -87.6298, "Chicago", "US"),
    "America/Los_Angeles": (34.0522, -118.2437, "Los Angeles", "US"),
    "America/Toronto": (43.6532, -79.3832, "Toronto", "CA"),
    "Asia/Tokyo": (35.6762, 139.6503, "Tokyo", "JP"),
    "Asia/Singapore": (1.3521, 103.8198, "Singapore", "SG"),
    "Australia/Sydney": (-33.8688, 151.2093, "Sydney", "AU"),
}


def tz_geo():
    tz = ""
    try:
        tz = Path("/etc/timezone").read_text().strip()
    except OSError:
        pass
    if not tz:
        code, out, _ = run(["timedatectl", "show", "-p", "Timezone", "--value"], 4)
        if code == 0:
            tz = out.strip()
    hit = TZ_COORDS.get(tz)
    if not hit:
        return None
    lat, lon, city, code = hit
    return {"lat": lat, "lon": lon, "city": city, "code": code, "ip": ""}


def you_geo(connected):
    # When the tunnel is up, the visible IP is the exit — don't call that "you".
    cached = load_json(GEO_PATH, {})
    if not connected:
        try:
            with urllib.request.urlopen(GEO_API, timeout=10) as response:
                payload = json.loads(response.read().decode("utf-8"))
            loc = payload.get("location") or {}
            if loc.get("latitude") is not None:
                geo = {
                    "lat": float(loc["latitude"]),
                    "lon": float(loc["longitude"]),
                    "city": loc.get("city") or "",
                    "code": str(loc.get("two_letter_iso_country_code") or ""),
                    "ip": str(payload.get("ip") or ""),
                }
                save_json(GEO_PATH, geo)
                return geo
        except (OSError, json.JSONDecodeError, ValueError):
            pass
    if cached.get("lat") is not None:
        return cached
    return tz_geo()


def live_status():
    """Query the daemon directly (works without password when it works at all)."""
    if not CLIENT.is_file():
        return None
    code, out, err = run([str(CLIENT), "status"], 15)
    text = (out or err or "").strip()
    if code != 0 or "Connected" not in text:
        return None
    # State: Connected wg to IP:port [ID] → IP:port [ID]
    m = re.search(r"Connected\s+(\w+)\s+to\s+(.+)", text)
    if not m:
        return None
    mode = m.group(1)
    route_text = m.group(2)
    hops = HOP.findall(route_text)
    if not hops:
        return None
    entry_host, _, entry_id = hops[0]
    exit_host, _, exit_id = hops[-1]
    return {
        "mode": mode,
        "entryId": entry_id,
        "exitId": exit_id,
        "entryHost": entry_host,
        "exitHost": exit_host,
    }


def _extract_json_at(data, start):
    depth = 0
    in_str = False
    esc = False
    for k in range(start, len(data)):
        c = data[k:k + 1]
        if esc:
            esc = False
            continue
        if c == b"\\":
            esc = True
            continue
        if c == b'"':
            in_str = not in_str
            continue
        if in_str:
            continue
        if c == b"{":
            depth += 1
        elif c == b"}":
            depth -= 1
            if depth == 0:
                return data[start:k + 1]
    return None


def app_cache_gateways():
    """Read the nym-vpn-app sled cache: every gateway it knows, with coords."""
    blobs_dir = Path.home() / ".local" / "share" / "nym-vpn-app" / "db" / "blobs"
    out = {}
    if not blobs_dir.is_dir():
        return out
    for blob in blobs_dir.iterdir():
        try:
            data = blob.read_bytes()
        except OSError:
            continue
        for key in (b"cache-wg-gateways", b"cache-mx-entry-gateways", b"cache-mx-exit-gateways"):
            i = data.find(key)
            if i == -1:
                continue
            j = data.find(b'{"expiry"', i)
            if j == -1:
                continue
            raw = _extract_json_at(data, j)
            if not raw:
                continue
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                continue
            for country in payload.get("value") or []:
                cc = str((country.get("country") or {}).get("code") or "").upper()
                for gw in country.get("gateways") or []:
                    gid = str(gw.get("id") or "")
                    loc = gw.get("location") or {}
                    lat, lon = loc.get("latitude"), loc.get("longitude")
                    if not gid or lat is None or lon is None:
                        continue
                    gtype = str(gw.get("type") or "")
                    role = "entry" if "entry" in gtype else "exit"
                    if gtype == "wg":
                        role = "wg"
                    out[gid] = {
                        "id": gid,
                        "lat": round(float(lat), 3),
                        "lon": round(float(lon), 3),
                        "code": cc,
                        "city": str(loc.get("city") or ""),
                        "name": str(gw.get("name") or ""),
                        "role": role,
                        "ip": str(gw.get("exitIpv4") or ""),
                        "score": str(gw.get("wgScore") or gw.get("mxScore") or ""),
                    }
    return out


def node_lookup():
    """Map identity key / ip → node with coordinates. App cache first, API fallback."""
    by_id = {}
    by_ip = {}
    for gid, n in app_cache_gateways().items():
        by_id[gid] = n
        if n.get("ip"):
            by_ip[n["ip"]] = n
    data = load_json(CATALOG_PATH, {})
    for n in data.get("nodes") or []:
        if n.get("id") and n["id"] not in by_id:
            by_id[n["id"]] = n
        if n.get("ip") and n["ip"] not in by_ip:
            by_ip[n["ip"]] = n
    return by_id, by_ip


def all_nodes():
    """Every gateway with coordinates, for the map. wg nodes get both roles."""
    seen = {}
    for gid, n in app_cache_gateways().items():
        seen[gid] = n
    data = load_json(CATALOG_PATH, {})
    for n in data.get("nodes") or []:
        if n.get("id") and n["id"] not in seen:
            seen[n["id"]] = n
    return list(seen.values())


def resolve_hop(node_id, host, by_id, by_ip):
    node = by_id.get(node_id) or by_ip.get(host)
    if node:
        return node
    # Identity in the directory may differ from the connected gateway identity;
    # fall back to matching nothing and let the caller mark it unknown.
    return None


def passive():
    daemon_code, daemon_out, _ = run(["systemctl", "is-active", "nym-vpnd.service"], 4)
    daemon = daemon_out.strip() if daemon_code == 0 else "inactive"
    _, links, _ = run(["ip", "-br", "link"], 4)
    up = set()
    for row in links.splitlines():
        parts = row.split()
        if len(parts) < 2:
            continue
        if parts[0] in {"tun0", "tun1"} and ",UP," in row:
            up.add(parts[0])
    connected = daemon == "active" and "tun0" in up and "tun1" in up

    # NEVER call nym-vpnc here. The daemon's polkit rule is auth_self and can
    # hang a background timer with a prompt nobody answers. The route comes
    # from the cache written by route-live (explicit user action).
    route = load_json(ROUTE_PATH, {})
    geo = you_geo(connected)
    mode = route.get("mode") or "wg"

    detail = ("Mixnet up" if mode == "mix" else "Two-hop tunnel up") if connected else "Tunnel down"
    if route.get("entry") and route.get("exit"):
        detail += " · " + str(route["entry"]) + " → " + str(route["exit"])
    return {
        "ok": True,
        "daemon": daemon or "unknown",
        "phase": "connected" if connected else "idle",
        "mode": mode,
        "twoHop": mode != "mix",
        "label": "Connected" if connected else "Off",
        "detail": detail,
        "entry": route.get("entry"),
        "exit": route.get("exit"),
        "entryName": route.get("entryName") or "",
        "exitName": route.get("exitName") or "",
        "entryLat": route.get("entryLat"),
        "entryLon": route.get("entryLon"),
        "exitLat": route.get("exitLat"),
        "exitLon": route.get("exitLon"),
        "entryCity": route.get("entryCity") or "",
        "exitCity": route.get("exitCity") or "",
        "entryHost": route.get("entryHost") or "",
        "exitHost": route.get("exitHost") or "",
        "youLat": geo.get("lat") if geo else None,
        "youLon": geo.get("lon") if geo else None,
        "youCity": (geo.get("city") or "") if geo else "",
        "youCode": (geo.get("code") or "") if geo else "",
        "live": False,
        "error": "",
    }


def route_live():
    """One explicit daemon session: read the real route and cache it."""
    payload = passive()
    live = live_status()
    if not live:
        payload["error"] = "daemon did not answer"
        return payload
    by_id, by_ip = node_lookup()
    entry_node = resolve_hop(live["entryId"], live["entryHost"], by_id, by_ip)
    exit_node = resolve_hop(live["exitId"], live["exitHost"], by_id, by_ip)
    route = load_json(ROUTE_PATH, {})
    route["mode"] = live["mode"]
    route["entryHost"] = live["entryHost"]
    route["exitHost"] = live["exitHost"]
    if entry_node:
        route["entry"] = entry_node.get("code")
        route["entryName"] = NAMES.get(entry_node.get("code"), entry_node.get("code"))
        route["entryCity"] = entry_node.get("city") or ""
        route["entryLat"] = entry_node.get("lat")
        route["entryLon"] = entry_node.get("lon")
    if exit_node:
        route["exit"] = exit_node.get("code")
        route["exitName"] = NAMES.get(exit_node.get("code"), exit_node.get("code"))
        route["exitCity"] = exit_node.get("city") or ""
        route["exitLat"] = exit_node.get("lat")
        route["exitLon"] = exit_node.get("lon")
    save_json(ROUTE_PATH, route)
    payload = passive()
    payload["live"] = True
    payload["mode"] = live["mode"]
    payload["twoHop"] = live["mode"] != "mix"
    return payload


def summarize(gateways):
    buckets = {}
    nodes = []
    for gateway in gateways:
        role = str(gateway.get("role") or "")
        if role not in {"EntryGateway", "ExitGateway"}:
            continue
        loc = gateway.get("location") or {}
        code = str(loc.get("two_letter_iso_country_code") or "").upper()
        lat = loc.get("latitude")
        lon = loc.get("longitude")
        if lat is not None and lon is not None:
            ips = gateway.get("ip_addresses") or []
            nodes.append({
                "lat": round(float(lat), 3),
                "lon": round(float(lon), 3),
                "role": "entry" if role == "EntryGateway" else "exit",
                "code": code,
                "id": str(gateway.get("identity_key") or ""),
                "ip": str(ips[0]) if ips else "",
                "city": loc.get("city") or "",
            })
        if not CODE.match(code):
            continue
        row = buckets.setdefault(code, {
            "code": code,
            "name": NAMES.get(code, code),
            "city": loc.get("city") or "",
            "lat": lat,
            "lon": lon,
            "entry": 0,
            "exit": 0,
            "_lats": [],
            "_lons": [],
        })
        if role == "EntryGateway":
            row["entry"] += 1
        else:
            row["exit"] += 1
        if lat is not None and lon is not None:
            row["_lats"].append(float(lat))
            row["_lons"].append(float(lon))
            if not row["city"]:
                row["city"] = loc.get("city") or ""
    countries = []
    for row in buckets.values():
        if row["_lats"]:
            row["lat"] = round(sum(row["_lats"]) / len(row["_lats"]), 4)
            row["lon"] = round(sum(row["_lons"]) / len(row["_lons"]), 4)
        del row["_lats"]
        del row["_lons"]
        countries.append(row)
    countries.sort(key=lambda item: item["name"])
    return {"ok": True, "fetched": int(time.time()), "countries": countries, "nodes": nodes}


def catalog(force=False):
    cached = load_json(CATALOG_PATH, None)
    fresh = (
        isinstance(cached, dict)
        and not force
        and time.time() - float(cached.get("fetched") or 0) < 6 * 3600
        and cached.get("countries")
        and cached.get("nodes")
    )
    if fresh:
        return cached
    try:
        with urllib.request.urlopen(API, timeout=25) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        if isinstance(cached, dict) and cached.get("countries"):
            cached["stale"] = True
            cached["error"] = str(error)[:160]
            return cached
        return {"ok": False, "countries": [], "error": str(error)[:160]}
    if not isinstance(payload, list):
        return {"ok": False, "countries": [], "error": "directory was not a list"}
    summary = summarize(payload)
    save_json(CATALOG_PATH, summary)
    return summary


def country_of(code):
    data = catalog()
    for row in data.get("countries") or []:
        if row.get("code") == code:
            return row
    return {"code": code, "name": NAMES.get(code, code), "city": "", "lat": None, "lon": None}


def remember(entry, exit_code):
    entry_row = country_of(entry)
    exit_row = country_of(exit_code)
    route = {
        "entry": entry,
        "exit": exit_code,
        "entryName": entry_row.get("name") or entry,
        "exitName": exit_row.get("name") or exit_code,
        "entryCity": entry_row.get("city") or "",
        "exitCity": exit_row.get("city") or "",
        "entryLat": entry_row.get("lat"),
        "entryLon": entry_row.get("lon"),
        "exitLat": exit_row.get("lat"),
        "exitLon": exit_row.get("lon"),
    }
    save_json(ROUTE_PATH, route)
    return route


def daemon_session(lines, timeout=50):
    if not CLIENT.is_file():
        return 1, "", "nym-vpnc is missing"
    script = "\n".join(lines + ["exit-session"]) + "\n"
    return run([str(CLIENT), "start-session"], timeout, script)


def parse_status(text):
    line = next((row.strip() for row in text.splitlines() if row.strip() and not row.strip().startswith("$")), "")
    state = line[6:].strip() if line.lower().startswith("state:") else line
    low = state.lower()
    if low.startswith("connected"):
        phase = "connected"
    elif "error" in low:
        phase = "error"
    elif "connect" in low:
        phase = "connecting"
    elif "disconnect" in low:
        phase = "disconnected"
    else:
        phase = "idle"
    pieces = ARROW.split(state, maxsplit=1)
    entry = HOP.search(pieces[0]).group(3) if pieces and HOP.search(pieces[0]) else ""
    exit_id = HOP.search(pieces[1]).group(3) if len(pieces) > 1 and HOP.search(pieces[1]) else ""
    return phase, state[:240], entry, exit_id


def apply_route(entry, exit_code, mode="wg"):
    entry = entry.upper()
    exit_code = exit_code.upper()
    if not CODE.match(entry) or not CODE.match(exit_code):
        return {"ok": False, "error": "Pick a two-letter entry and exit country"}
    if entry == exit_code:
        return {"ok": False, "error": "Entry and exit must be different countries"}
    route = remember(entry, exit_code)
    route["mode"] = "mix" if mode == "mix" else "wg"
    save_json(ROUTE_PATH, route)
    two_hop = "off" if route["mode"] == "mix" else "on"
    code, out, err = daemon_session([
        f"tunnel set --two-hop {two_hop}",
        f"gateway set --entry-country {entry} --exit-country {exit_code}",
        "connect",
        "status",
    ], 90)
    phase, raw, entry_id, exit_id = parse_status(out or err)
    payload = passive()
    payload.update(route)
    payload["ok"] = code == 0
    payload["phase"] = phase if phase != "idle" else payload["phase"]
    payload["raw"] = raw
    payload["entryId"] = entry_id
    payload["exitId"] = exit_id
    payload["message"] = "Route sent. The daemon may ask once."
    payload["error"] = "" if code == 0 else (err or out or "daemon refused")[-180:]
    return payload


def set_mode(mode):
    mode = "mix" if mode == "mix" else "wg"
    route = load_json(ROUTE_PATH, {})
    route["mode"] = mode
    save_json(ROUTE_PATH, route)
    two_hop = "off" if mode == "mix" else "on"
    code, out, err = daemon_session([f"tunnel set --two-hop {two_hop}", "tunnel get"], 60)
    payload = passive()
    payload["ok"] = code == 0
    payload["mode"] = mode
    payload["twoHop"] = mode != "mix"
    payload["detail"] = ("Mixnet 5-hop" if mode == "mix" else "WireGuard 2-hop") + " set"
    payload["error"] = "" if code == 0 else (err or out or "mode change failed")[-180:]
    return payload


def iface_bytes():
    total_rx = 0
    total_tx = 0
    for iface in ("tun0", "tun1"):
        base = Path("/sys/class/net") / iface / "statistics"
        try:
            total_rx += int((base / "rx_bytes").read_text().strip())
            total_tx += int((base / "tx_bytes").read_text().strip())
        except (OSError, ValueError):
            continue
    return total_rx, total_tx


def ping_ms(host, timeout=2):
    if not host:
        return None
    code, out, _ = run(["ping", "-c", "1", "-W", str(timeout), host], timeout + 2)
    if code != 0:
        return None
    m = re.search(r"time[=<]([0-9.]+)\s*ms", out)
    return round(float(m.group(1)), 1) if m else None


def stats():
    payload = passive()
    rx0, tx0 = iface_bytes()
    time.sleep(1.0)
    rx1, tx1 = iface_bytes()
    payload["rxRate"] = max(0, rx1 - rx0)
    payload["txRate"] = max(0, tx1 - tx0)
    payload["rxTotal"] = rx1
    payload["txTotal"] = tx1
    if payload["phase"] == "connected":
        if payload.get("entryHost"):
            payload["entryPing"] = ping_ms(payload["entryHost"])
        if payload.get("exitHost"):
            payload["exitPing"] = ping_ms(payload["exitHost"])
    return payload


def disconnect():
    code, out, err = daemon_session(["disconnect", "status"])
    payload = passive()
    payload["ok"] = code == 0
    payload["phase"] = "disconnected" if code == 0 else payload["phase"]
    payload["detail"] = "Disconnect sent"
    payload["error"] = "" if code == 0 else (err or out or "disconnect failed")[-180:]
    return payload


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "status":
        payload = passive()
    elif command == "stats":
        payload = stats()
    elif command == "route-live":
        payload = route_live()
    elif command == "catalog":
        payload = catalog(force="--force" in sys.argv[2:])
    elif command == "apply" and len(sys.argv) >= 4:
        payload = apply_route(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "wg")
    elif command == "mode" and len(sys.argv) >= 3:
        payload = set_mode(sys.argv[2])
    elif command == "disconnect":
        payload = disconnect()
    else:
        payload = {"ok": False, "error": "unknown command"}
    json.dump(payload, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
