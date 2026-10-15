#!/usr/bin/env python3
"""Nym bar helper v2 — full daemon surface behind one JSON CLI.

Timer paths (status/stats) never touch the daemon socket. Session commands
may return authBlocked when polkit cannot be answered; the panel shows the
fix instructions shipped in the error text.
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CLIENT = ROOT / "bin" / "nym-vpnc"
if not CLIENT.is_file():
    for cand in ("/usr/bin/nym-vpnc", "/usr/local/bin/nym-vpnc"):
        if Path(cand).is_file():
            CLIENT = Path(cand)
            break

CACHE = Path.home() / ".cache" / "omarchy"
CATALOG_PATH = CACHE / "nym-countries.json"
ROUTE_PATH = CACHE / "nym-route.json"
GEO_PATH = CACHE / "nym-geo.json"
API = "https://nymvpn.com/api/public/v1/directory/gateways?show_vpn_only=true"
GEO_API = "https://nymvpn.com/api/public/v1/geo/ip"
CODE = re.compile(r"^[A-Z]{2}$")
HOP = re.compile(r"([0-9A-Za-z.:]+):(\d+)\s+\[([A-Za-z0-9]+)\]")
ARROW = re.compile(r"\s+(?:→|->)\s+")
AUTH_FIX = (
    "Polkit blocked the daemon. Run once: "
    "echo 'polkit.addRule(function(a,s){ if (a.id == "
    '"com.nymvpn.vpnd.unix-access" && s.active) return polkit.Result.YES; '
    "});' | sudo tee /etc/polkit-1/rules.d/49-nymvpn.rules && "
    "sudo systemctl try-restart polkit"
)

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
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except OSError as error:
        return 1, "", str(error)
    return done.returncode, done.stdout or "", done.stderr or ""


def daemon_active():
    code, out, _ = run(["systemctl", "is-active", "nym-vpnd.service"], 4)
    return code == 0 and out.strip() == "active"


def load_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return fallback


def save_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=True) + "\n")


def kv(text):
    out = {}
    for row in text.splitlines():
        if ":" not in row:
            continue
        key, _, val = row.partition(":")
        out[key.strip().lower()] = val.strip()
    return out


def onoff(val):
    return str(val or "").strip().lower() == "on"


def boolstr(val):
    return str(val or "").strip().lower() == "true"


# ---------------------------------------------------------------------------
# Parsers — formats verified against nym-vpnc v2026.12.4 / daemon v2026.13.0
# ---------------------------------------------------------------------------

def parse_tunnel(text):
    d = kv(text)
    return {
        "ipv6": onoff(d.get("ipv6")),
        "twoHop": onoff(d.get("two-hop")),
        "netstack": onoff(d.get("netstack")),
        "circumvention": onoff(d.get("circumvention transports")),
        "poissonDisabled": boolstr(d.get("disable_poisson_rate")),
    }


def parse_gateway_get(text):
    entry = ""
    exitp = ""
    residential = False
    for row in text.splitlines():
        if row.startswith("Entry point:"):
            entry = row.partition(":")[2].strip()
        elif row.startswith("Exit point:"):
            exitp = row.partition(":")[2].strip()
        elif row.startswith("Residential exit:"):
            residential = onoff(row.partition(":")[2])
    def describe(raw):
        auto = raw.startswith("Auto")
        # (?<![A-Za-z_]) so "exclude_user_country: true" doesn't fake a code
        m = re.search(r"(?<![A-Za-z_])country:\s*([A-Za-z]{2})(?![A-Za-z])", raw)
        code = m.group(1).upper() if m else ""
        return auto, code
    entry_auto, entry_code = describe(entry)
    exit_auto, exit_code = describe(exitp)
    return {
        "entryAuto": entry_auto,
        "entryCode": entry_code,
        "entryDetail": entry[:120],
        "exitAuto": exit_auto,
        "exitCode": exit_code,
        "exitDetail": exitp[:120],
        "residential": residential,
    }


def parse_account_get(text):
    ident = ""
    mode = ""
    state = ""
    for row in text.splitlines():
        if row.startswith("Account identity:"):
            ident = row.partition(":")[2].strip()
        elif row.startswith("Account mode:"):
            mode = row.partition(":")[2].strip()
        elif row.startswith("Account state:"):
            state = row.partition(":")[2].strip()
    if not ident:
        m = re.search(r"(n1[02-9ac-hj-np-z38-9]{20,})", text)
        ident = m.group(1) if m else ""
    logged = bool(ident) and "not" not in text.lower()[:80]
    return {"loggedIn": logged, "identity": ident,
            "mode": mode, "state": state}


def parse_account_summary(text):
    def grab(pattern, cast=str):
        m = re.search(pattern, text)
        return cast(m.group(1)) if m else None  # type: ignore[operator]
    return {
        "quotaUsedGb": grab(r"traffic_used_gb:\s*([0-9]+)", int),
        "quotaLimitGb": grab(r"traffic_limit_gb:\s*([0-9]+)", int),
        "quotaReset": grab(r"traffic_reset_time:\s*Some\(\s*([0-9\-]+)") or "",
        "devicesLeft": grab(r"remaining_devices:\s*([0-9]+)", int),
        "subscriptionKind": grab(r"kind:\s*([A-Za-z]+)\s*,?\s*\n"),
        "subscriptionStatus": grab(r"status:\s*\"?([A-Za-z]+)\"?\s*,?\s*\n\s*\},\s*\n\s*\)\s*,?\s*\n\s*\),\s*\n\s*is_subscription_stacked") or grab(r"subscription:\s*[A-Za-z]+\s*\{[^}]*status:\s*\"([a-z]+)\""),
    }


def parse_dns(text):
    m = re.match(r"Custom DNS:\s*(Enabled|Disabled)\s*\[(.*)\]", text.strip())
    if not m:
        return {"enabled": False, "servers": []}
    servers = [s.strip().strip('"').strip("'") for s in m.group(2).split(",") if s.strip()]
    return {"enabled": m.group(1) == "Enabled", "servers": servers}


def parse_dns_default(text):
    m = re.match(r"Default DNS:\s*(.*)", text.strip())
    return [s for s in (m.group(1).split() if m else []) if s]


def parse_lan(text):
    m = re.search(r"policy:\s*(allow|block)", text)
    return m.group(1) if m else ""


def parse_adblock(text):
    m = re.search(r"Ad blocking:\s*(on|off)", text)
    return m.group(1) == "on" if m else False


def parse_socks5(text):
    d = kv(text)
    state = d.get("state", "")
    addr = d.get("socks5 listen address", "")
    addr = addr if addr and addr.lower() != "none" else ""
    conns = d.get("active connections", "0")
    try:
        conns = int(conns)
    except ValueError:
        conns = 0
    return {"enabled": state.lower() == "enabled", "address": addr,
            "connections": conns}


def parse_excluded_processes(text):
    if "no excluded" in text.lower():
        return []
    pids = []
    for tok in re.split(r"[\s,]+", text):
        if tok.isdigit():
            pids.append(int(tok))
    return sorted(set(pids))


def parse_geo_exclusion(text):
    d = kv(text)
    enabled = d.get("geo exclusion enabled", "").lower() == "yes"
    port = d.get("listen port", "0")
    countries = [c.strip().upper() for c in d.get("excluded countries", "").split(",") if c.strip()]
    try:
        port = int(port)
    except ValueError:
        port = 0
    return {"enabled": enabled, "port": port, "countries": countries}


def parse_network_stats(text):
    d = kv(text)
    return {
        "enabled": onoff(d.get("anonymous network statistics collection")),
        "allowDisconnected": onoff(d.get("disconnected reporting")),
    }


def parse_favorites(text):
    def side(label):
        m = re.search(label + r":\s*\[(.*?)\]", text, re.S)
        if not m:
            return []
        body = m.group(1)
        items = []
        for entry in re.findall(r"(?:Country|Id|Region)\s*\{([^}]*)\}", body):
            code = ""
            cid = ""
            kind = "country"
            cm = re.search(r"country:\s*\"?([A-Za-z]{2})\"?", entry)
            im = re.search(r"id:\s*\"?([1-9A-HJ-NP-Za-km-z]+)\"?", entry)
            if cm:
                code = cm.group(1).upper()
            if im:
                cid = im.group(1)
                kind = "id"
            items.append({"kind": kind, "code": code, "id": cid,
                          "raw": entry.strip()[:80]})
        if not items and body.strip():
            for cc in re.findall(r"[A-Z]{2}", body):
                items.append({"kind": "country", "code": cc, "id": "", "raw": cc})
        return items
    return {"entry": side("entry"), "exit": side("exit")}


def parse_recents(text):
    """Recent entry/exit gateway tables in one output."""
    def table_rows(tbl):
        rows = []
        lines = [l for l in tbl.splitlines() if "|" in l and "-" not in l[:3]]
        if len(lines) < 2:
            return rows
        for line in lines[1:]:
            cells = [c.strip() for c in line.split("|")]
            if len(cells) < 5 or cells[0].lower().startswith("id"):
                continue
            gid, name, location, perf = cells[0], cells[1], cells[2], cells[3]
            ipv4 = cells[4] if len(cells) > 4 else ""
            score = perf.split("(")[0].strip()
            cc = ""
            mm = re.search(r"\[([A-Z]{2})\]", location)
            if mm:
                cc = mm.group(1)
            rows.append({"id": gid, "name": name, "location": location,
                         "score": score, "ipv4": ipv4, "code": cc})
        return rows

    parts = re.split(r"Recent (entry|exit) gateways for:", text)
    out = {"entry": [], "exit": []}
    for i in range(1, len(parts) - 1, 2):
        side = parts[i].strip().lower()
        if side.startswith("entry"):
            out["entry"] = table_rows(parts[i + 1])
        else:
            out["exit"] = table_rows(parts[i + 1])
    if not out["entry"] and not out["exit"]:
        # Single-table variant without headers
        rows = table_rows(text)
        out["entry"] = rows
    return out


def parse_split_tunnel_supported(text):
    return "supported" in text.lower()


# ---------------------------------------------------------------------------
# Session plumbing
# ---------------------------------------------------------------------------

def session(lines, timeout=50):
    if not CLIENT.is_file():
        return False, "nym-vpnc is missing", False
    script = "\n".join(lines + ["exit-session"]) + "\n"
    code, out, err = run([str(CLIENT), "start-session"], timeout, script)
    if code == 124:
        return False, "", True
    return code == 0, (out or "") + (err or ""), False


def session_blocks(text, n):
    parts = re.split(r"(?m)^\$\s?", text)
    parts = parts[1:] if parts and not parts[0].strip() else parts
    while len(parts) < n:
        parts.append("")
    return parts[:n]


def auth_blocked():
    return {"ok": False, "authBlocked": True, "error": AUTH_FIX}


# ---------------------------------------------------------------------------
# Passive status (never touches the daemon socket)
# ---------------------------------------------------------------------------

TZ_COORDS = {
    "Europe/Copenhagen": (55.6761, 12.5683, "Copenhagen", "DK"),
    "Europe/Stockholm": (59.3293, 18.0686, "Stockholm", "SE"),
    "Europe/Berlin": (52.52, 13.405, "Berlin", "DE"),
    "Europe/London": (51.5074, -0.1278, "London", "GB"),
    "Europe/Paris": (48.8566, 2.3522, "Paris", "FR"),
    "Europe/Amsterdam": (52.3676, 4.9041, "Amsterdam", "NL"),
    "Europe/Madrid": (40.4168, -3.7038, "Madrid", "ES"),
    "Europe/Rome": (41.9028, 12.4964, "Rome", "IT"),
    "Europe/Warsaw": (52.2297, 21.0122, "Warsaw", "PL"),
    "Europe/Helsinki": (60.1699, 24.9384, "Helsinki", "FI"),
    "Europe/Oslo": (59.9139, 10.7522, "Oslo", "NO"),
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


def resolve_hop(node_id, host, by_id, by_ip):
    return by_id.get(node_id) or by_ip.get(host)


def live_status():
    if not CLIENT.is_file():
        return None
    code, out, err = run([str(CLIENT), "status"], 15)
    text = (out or err or "").strip()
    if code != 0 or "Connected" not in text:
        return None
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


def passive():
    daemon_code, daemon_out, _ = run(["systemctl", "is-active", "nym-vpnd.service"], 4)
    daemon = daemon_out.strip() if daemon_code == 0 else "inactive"
    _, links, _ = run(["ip", "-br", "link"], 4)
    up = False
    for row in links.splitlines():
        parts = row.split()
        if len(parts) >= 2 and parts[0] in {"tun0", "tun1"} and "UP" in row:
            up = True
            break
    connected = daemon == "active" and up

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
        # Even the no-auth status path can hang behind the polkit gate while
        # the tunnel is up; interface state already answers "connected".
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


# ---------------------------------------------------------------------------
# Catalog (public directory)
# ---------------------------------------------------------------------------

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
        return {"ok": False, "countries": [], "nodes": [], "error": str(error)[:160]}
    if not isinstance(payload, list):
        return {"ok": False, "countries": [], "nodes": [], "error": "directory was not a list"}
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


# ---------------------------------------------------------------------------
# full — one batched read of everything the panel needs
# ---------------------------------------------------------------------------

FULL_COMMANDS = [
    ("tunnel", "tunnel get"),
    ("gateway", "gateway get"),
    ("accountGet", "account get"),
    ("accountSummary", "account summary"),
    ("dns", "dns get"),
    ("dnsDefault", "dns get-default"),
    ("lan", "lan get"),
    ("adBlock", "ad-block get"),
    ("socks5", "socks5 status"),
    ("splitTunnel", "split-tunnel get"),
    ("excluded", "split-tunnel excluded-processes"),
    ("geoExclusion", "geo-exclusion get"),
    ("networkStats", "network-stats get"),
    ("network", "network get"),
    ("favorites", "favorites get"),
    ("recentsWg", "gateway recents wg"),
]


def full():
    payload = passive()
    payload["authed"] = False
    payload["favorites"] = {"entry": [], "exit": []}
    payload["recents"] = {"wgEntry": [], "wgExit": [], "mixEntry": [], "mixExit": []}
    payload["splitSupported"] = False
    payload["excludedProcesses"] = []
    payload["geoExclusion"] = {"enabled": False, "port": 0, "countries": []}
    payload["networkStats"] = {"enabled": False, "allowDisconnected": False}
    payload["network"] = ""

    if not daemon_active():
        payload["error"] = payload.get("error") or "daemon is not running"
        return payload

    lines = [cmd for _, cmd in FULL_COMMANDS]
    ok, text, timed_out = session(lines, timeout=30)
    if timed_out:
        payload.update(auth_blocked())
        return payload

    blocks = session_blocks(text, len(FULL_COMMANDS))
    payload["authed"] = True

    payload["tunnel"] = parse_tunnel(blocks[0])
    payload["gateway"] = parse_gateway_get(blocks[1])
    acc = parse_account_get(blocks[2])
    summ = parse_account_summary(blocks[3])
    acc.update({k: v for k, v in summ.items() if v is not None})
    payload["account"] = acc
    payload["dns"] = parse_dns(blocks[4])
    payload["dns"]["defaults"] = parse_dns_default(blocks[5])
    payload["lan"] = parse_lan(blocks[6])
    payload["adBlock"] = parse_adblock(blocks[7])
    payload["socks5"] = parse_socks5(blocks[8])
    payload["splitSupported"] = parse_split_tunnel_supported(blocks[9])
    payload["excludedProcesses"] = parse_excluded_processes(blocks[10])
    payload["geoExclusion"] = parse_geo_exclusion(blocks[11])
    payload["networkStats"] = parse_network_stats(blocks[12])
    payload["network"] = blocks[13].strip().replace("Current network:", "").strip()
    payload["favorites"] = parse_favorites(blocks[14])
    wg_rec = parse_recents(blocks[15])
    payload["recents"]["wgEntry"] = wg_rec["entry"]
    payload["recents"]["wgExit"] = wg_rec["exit"]

    gw = payload["gateway"]
    if gw.get("entryCode"):
        payload["entry"] = gw["entryCode"]
        row = country_of(gw["entryCode"])
        payload["entryName"] = row.get("name") or gw["entryCode"]
    if gw.get("exitCode"):
        payload["exit"] = gw["exitCode"]
        row = country_of(gw["exitCode"])
        payload["exitName"] = row.get("name") or gw["exitCode"]
    tunnel = payload.get("tunnel") or {}
    if tunnel:
        payload["mode"] = "wg" if tunnel.get("twoHop", True) else "mix"
        payload["twoHop"] = bool(tunnel.get("twoHop", True))
    return payload


# ---------------------------------------------------------------------------
# Actions (explicit user action only)
# ---------------------------------------------------------------------------

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
    em = HOP.search(pieces[0]) if pieces else None
    xm = HOP.search(pieces[1]) if len(pieces) > 1 else None
    entry = em.group(3) if em else ""
    exit_id = xm.group(3) if xm else ""
    return phase, state[:240], entry, exit_id


def action_result(ok, text, timed_out, extra_lines=0, timeout_note=""):
    if timed_out:
        payload = auth_blocked() if daemon_active() else {"ok": False, "error": "daemon did not answer"}
        payload.update(passive())
        return payload
    parts = [p for p in re.split(r"(?m)^\$\s?", text) if p.strip()]
    status_text = parts[-1] if parts else ""
    phase, raw, entry_id, exit_id = parse_status(status_text)
    payload = passive()
    payload.update({"ok": ok, "phase": phase if phase != "idle" else payload["phase"],
                    "raw": raw, "entryId": entry_id, "exitId": exit_id,
                    "message": "Sent. The daemon may ask once.",
                    "error": "" if ok else (text or "daemon refused")[-180:]})
    return payload


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
    ok, text, timed_out = session([
        f"tunnel set --two-hop {two_hop}",
        f"gateway set --entry-country {entry} --exit-country {exit_code}",
        "connect",
        "status",
    ], 90)
    payload = action_result(ok, text, timed_out)
    payload.update(route)
    return payload


def quick(mode):
    mode = "mix" if mode == "mix" else "wg"
    route = load_json(ROUTE_PATH, {})
    route["mode"] = mode
    route["entry"] = ""
    route["exit"] = ""
    save_json(ROUTE_PATH, route)
    two_hop = "off" if mode == "mix" else "on"
    ok, text, timed_out = session([
        f"tunnel set --two-hop {two_hop}",
        "connect",
        "status",
    ], 90)
    return action_result(ok, text, timed_out)


def reconnect():
    ok, text, timed_out = session(["reconnect", "status"], 90)
    return action_result(ok, text, timed_out)


def disconnect():
    ok, text, timed_out = session(["disconnect", "status"], 60)
    payload = action_result(ok, text, timed_out)
    if ok:
        payload["phase"] = "disconnected"
        payload["detail"] = "Disconnect sent"
    return payload


def set_mode(mode):
    mode = "mix" if mode == "mix" else "wg"
    route = load_json(ROUTE_PATH, {})
    route["mode"] = mode
    save_json(ROUTE_PATH, route)
    two_hop = "off" if mode == "mix" else "on"
    ok, text, timed_out = session([f"tunnel set --two-hop {two_hop}", "tunnel get"], 60)
    payload = passive()
    payload["ok"] = ok and not timed_out
    payload["mode"] = mode
    payload["twoHop"] = mode != "mix"
    payload["tunnel"] = parse_tunnel(text) if text else payload.get("tunnel", {})
    payload["detail"] = ("Mixnet 5-hop" if mode == "mix" else "WireGuard 2-hop") + " set"
    if timed_out:
        payload.update(auth_blocked())
    elif not ok:
        payload["error"] = (text or "mode change failed")[-180:]
    return payload


def simple_action(lines, timeout=60, ok_hint=""):
    ok, text, timed_out = session(lines, timeout)
    if timed_out:
        payload = auth_blocked() if daemon_active() else {"ok": False, "error": "daemon did not answer"}
        payload.update(passive())
        return payload
    payload = passive()
    payload["ok"] = ok
    if ok_hint:
        payload["detail"] = ok_hint
    if not ok:
        payload["error"] = (text or "daemon refused")[-180:]
    return payload


def login():
    mnemonic = os.environ.get("NYM_MNEMONIC", "").strip()
    if not mnemonic:
        return {"ok": False, "error": "missing mnemonic"}
    mnemonic = " ".join(mnemonic.split())
    safe = mnemonic.replace('"', "")
    return simple_action([f'account set "{safe}"', "account get"], 60, "Account login sent")


def logout():
    return simple_action(["account forget"], 60, "Account forgotten")


def rotate_keys():
    return simple_action(["account rotate-keys"], 60, "Key rotation requested")


def favorite(op, code):
    code = code.upper()
    if not CODE.match(code):
        return {"ok": False, "error": "Pick a two-letter country"}
    table = {
        "fav-add-entry": ["favorites set-entry country " + code],
        "fav-add-exit": ["favorites set-exit country " + code],
        "fav-remove-entry": ["favorites remove-entry country " + code],
        "fav-remove-exit": ["favorites remove-exit country " + code],
    }
    return simple_action(table[op], 30, "Favorite updated")


def toggle(key, state):
    state = "on" if state == "on" else "off"
    table = {
        "lan": ["lan set " + ("allow" if state == "on" else "block")],
        "adblock": ["ad-block set " + state],
        "ipv6": ["tunnel set --ipv6 " + state],
        "netstack": ["tunnel set --netstack " + state],
        "ct": ["tunnel set --circumvention-transports " + state],
        "netstats": ["network-stats set --enabled " + state],
    }
    if key not in table:
        return {"ok": False, "error": "unknown toggle"}
    return simple_action(table[key], 30)


def dns_op(op, arg=""):
    if op == "set":
        servers = " ".join([s for s in re.split(r"[,\s]+", arg) if s])
        if not servers:
            return {"ok": False, "error": "no DNS servers given"}
        if not re.match(r"^[0-9a-fA-F.,:\s]+$", servers):
            return {"ok": False, "error": "invalid DNS server list"}
        return simple_action(["dns set " + servers, "dns get"], 30)
    if op == "clear":
        return simple_action(["dns clear"], 30)
    if op in ("enable", "disable"):
        return simple_action(["dns " + op], 30)
    return {"ok": False, "error": "unknown dns op"}


def socks5(op, addr="", exit_code=""):
    if op == "off":
        return simple_action(["socks5 disable"], 30)
    if not addr or ":" not in addr:
        return {"ok": False, "error": "listen address like 127.0.0.1:1080 required"}
    line = f"socks5 enable --socks5-address {addr}"
    if CODE.match((exit_code or "").upper()):
        line += f" --exit-country {exit_code.upper()}"
    return simple_action([line, "socks5 status"], 45)


def split_op(op, pid=""):
    if op == "add":
        if not pid.isdigit():
            return {"ok": False, "error": "PID must be a number"}
        return simple_action([f"split-tunnel add-process {pid}"], 30)
    if op == "remove":
        if not pid.isdigit():
            return {"ok": False, "error": "PID must be a number"}
        return simple_action([f"split-tunnel remove-process {pid}"], 30)
    if op == "clear":
        return simple_action(["split-tunnel clear-processes"], 30)
    return {"ok": False, "error": "unknown split op"}


def diag():
    ok, text, timed_out = session(["diagnostic run"], 240)
    if timed_out:
        payload = auth_blocked() if daemon_active() else {"ok": False, "error": "daemon did not answer"}
        payload.update(passive())
        return payload
    payload = passive()
    payload["ok"] = ok
    payload["raw"] = text[-4000:]
    if not ok:
        payload["error"] = (text or "diagnostic failed")[-180:]
    return payload


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    argv = sys.argv[1:]
    command = argv[0] if argv else "status"
    arg = argv[1:]

    if command == "status":
        payload = passive()
    elif command == "full":
        payload = full()
    elif command == "stats":
        payload = stats()
    elif command == "route-live":
        payload = route_live()
    elif command == "catalog":
        payload = catalog(force="--force" in arg)
    elif command == "apply" and len(arg) >= 3:
        payload = apply_route(arg[0], arg[1], arg[2])
    elif command == "quick" and len(arg) >= 1:
        payload = quick(arg[0])
    elif command == "reconnect":
        payload = reconnect()
    elif command == "disconnect":
        payload = disconnect()
    elif command == "mode" and len(arg) >= 1:
        payload = set_mode(arg[0])
    elif command == "login":
        payload = login()
    elif command == "logout":
        payload = logout()
    elif command == "rotate-keys":
        payload = rotate_keys()
    elif command in ("fav-add-entry", "fav-add-exit", "fav-remove-entry", "fav-remove-exit") and len(arg) >= 1:
        payload = favorite(command, arg[0])
    elif command == "toggle" and len(arg) >= 2:
        payload = toggle(arg[0], arg[1])
    elif command == "dns" and len(arg) >= 1:
        payload = dns_op(arg[0], arg[1] if len(arg) > 1 else "")
    elif command == "socks5" and len(arg) >= 1:
        payload = socks5(arg[0], arg[1] if len(arg) > 1 else "", arg[2] if len(arg) > 2 else "")
    elif command == "split" and len(arg) >= 1:
        payload = split_op(arg[0], arg[1] if len(arg) > 1 else "")
    elif command == "diag":
        payload = diag()
    else:
        payload = {"ok": False, "error": "unknown command"}

    json.dump(payload, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
