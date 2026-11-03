"""Shared CalDAV + iCalendar helpers (caldav-tasks.py, caldav-events.py).
Standard library only."""
import base64
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import qsconf

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "cs": "http://calendarserver.org/ns/",
      "ical": "http://apple.com/ns/ical/"}
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "quickshell")


class Fail(Exception):
    pass


# ---- HTTP -------------------------------------------------------------------------
class Client:
    def __init__(self, cfg):
        user = cfg.get("username", "")
        pw = cfg.get("password", "")
        if not pw and cfg.get("passwordCommand"):
            pw = subprocess.run(cfg["passwordCommand"], shell=True, capture_output=True,
                                text=True, check=True).stdout.rstrip("\n")
        if not user or not pw:
            raise Fail("no CalDAV credentials: set tasks.username/password in "
                       "~/.local/share/quickshell/private.json")
        self.auth = "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode()

    def request(self, method, url, body=None, headers=None, depth=None, _hops=0):
        h = {"Authorization": self.auth, "User-Agent": qsconf.UA}
        if body is not None:
            h["Content-Type"] = "application/xml; charset=utf-8" if body.lstrip().startswith(b"<") \
                else "text/calendar; charset=utf-8"
        if depth is not None:
            h["Depth"] = str(depth)
        h.update(headers or {})
        req = urllib.request.Request(url, data=body, method=method, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            # urllib does not follow redirects for PROPFIND/REPORT
            if e.code in (301, 302, 307, 308) and _hops < 5 and e.headers.get("Location"):
                return self.request(method, urllib.parse.urljoin(url, e.headers["Location"]),
                                    body, headers, depth, _hops + 1)
            if e.code == 401:
                raise Fail("CalDAV: authentication failed (401)") from None
            raise Fail(f"CalDAV {method} {url}: HTTP {e.code}") from None
        except urllib.error.URLError as e:
            raise Fail(f"CalDAV: {e.reason}") from None

    def propfind(self, url, props, depth=0):
        body = ('<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:" '
                'xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" '
                'xmlns:ical="http://apple.com/ns/ical/">'
                f'<d:prop>{props}</d:prop></d:propfind>').encode()
        _, _, data = self.request("PROPFIND", url, body, depth=depth)
        return ET.fromstring(data)


def href_of(resp, base):
    return urllib.parse.urljoin(base, resp.findtext("d:href", "", NS))


# ---- discovery ----------------------------------------------------------------------
def calendars(cli, url):
    """all calendar collections: [{href, name, color, todo, event}]"""
    root = cli.propfind(url, "<d:current-user-principal/>")
    p = root.find(".//d:current-user-principal/d:href", NS)
    principal = urllib.parse.urljoin(url, p.text) if p is not None else url
    root = cli.propfind(principal, "<c:calendar-home-set/>")
    h = root.find(".//c:calendar-home-set/d:href", NS)
    home = urllib.parse.urljoin(principal, h.text) if h is not None else principal
    root = cli.propfind(home, "<d:displayname/><d:resourcetype/><c:supported-calendar-component-set/>"
                              "<ical:calendar-color/>", 1)
    out = []
    for r in root.findall("d:response", NS):
        if r.find(".//d:resourcetype/c:calendar", NS) is None:
            continue
        comps = [c.get("name") for c in r.findall(".//c:supported-calendar-component-set/c:comp", NS)]
        href = href_of(r, home)
        name = r.findtext(".//d:displayname", "", NS) or href.rstrip("/").rsplit("/", 1)[-1]
        color = (r.findtext(".//ical:calendar-color", "", NS) or "").strip()
        if re.fullmatch(r"#[0-9A-Fa-f]{8}", color):
            color = color[:7]                          # #RRGGBBAA -> #RRGGBB
        out.append({"href": href, "name": name, "color": color,
                    "todo": not comps or "VTODO" in comps, "event": not comps or "VEVENT" in comps})
    return out


def cached_calendars(cli, url, refresh=False, max_age=24 * 3600):
    """calendars() cached for a day (discovery costs three PROPFINDs)"""
    path = os.path.join(CACHE_DIR, "caldav-calendars.json")
    try:
        with open(path) as f:
            c = json.load(f)
        if not refresh and c.get("url") == url and time.time() - c.get("time", 0) < max_age:
            return c["calendars"]
    except (OSError, ValueError):
        pass
    cals = calendars(cli, url)
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "w") as f:
        json.dump({"url": url, "time": time.time(), "calendars": cals}, f)
    return cals


# ---- iCalendar ------------------------------------------------------------------------
def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).replace("\r\n", "\n").split("\n")


def fold(line):
    out, b = [], line.encode()
    while len(b) > 75:
        cut = 75 if not out else 74
        while cut > 0 and (b[cut] & 0xC0) == 0x80:   # don't split UTF-8 sequences
            cut -= 1
        out.append(b[:cut].decode())
        b = b[cut:]
    out.append(b.decode())
    return "\r\n ".join(out)


def split_prop(line):
    m = re.match(r"([^:;]+)((?:;[^:]*)?):(.*)", line)
    if not m:
        return None, {}, ""
    params = {}
    for p in filter(None, m.group(2).split(";")):
        k, _, v = p.partition("=")
        params[k.upper()] = v.strip('"')
    return m.group(1).upper(), params, m.group(3)


def unescape(v):
    return re.sub(r"\\([\\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), v)


def escape(v):
    return v.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def parse_dt(value, params):
    """-> (datetime aware or date, all_day)"""
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return datetime.strptime(value[:8], "%Y%m%d").date(), True
    dt = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    if value.endswith("Z"):
        return dt.replace(tzinfo=timezone.utc), False
    try:
        return dt.replace(tzinfo=ZoneInfo(params["TZID"])) if "TZID" in params else dt.astimezone(), False
    except Exception:  # noqa: BLE001 - unknown TZID: treat as local time
        return dt.astimezone(), False


def parse_duration(value):
    """RFC 5545 DURATION (e.g. P1D, PT1H30M, -P1W) -> timedelta"""
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", value.strip())
    if not m:
        return timedelta(0)
    w, d, h, mi, s = (int(x or 0) for x in m.groups()[1:])
    td = timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)
    return -td if m.group(1) == "-" else td


def epoch_ms(d):
    if isinstance(d, datetime):
        return int(d.timestamp() * 1000)
    return int(datetime(d.year, d.month, d.day).astimezone().timestamp() * 1000)


def components(lines, kind):
    """top-level components of `kind` (e.g. "VEVENT") -> list of their property
    lines (nested blocks such as VALARM skipped)"""
    out, cur, depth = [], None, 0
    for line in lines:
        if cur is None:
            if line == f"BEGIN:{kind}":
                cur, depth = [], 0
            continue
        if line == f"END:{kind}" and depth == 0:
            out.append(cur)
            cur = None
        elif line.startswith("BEGIN:"):
            depth += 1
        elif line.startswith("END:"):
            depth -= 1
        elif depth == 0:
            cur.append(line)
    return out


def utcstamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def block(lines, kind):
    """(begin, end) line indices of the first `kind` component, or (None, None)"""
    try:
        s = lines.index(f"BEGIN:{kind}")
        return s, lines.index(f"END:{kind}", s)
    except ValueError:
        return None, None


def set_props(lines, changes, kind):
    """changes: {NAME: full line or None (remove)} at the top level of the first
    `kind` component (nested blocks like VALARM are left alone)"""
    s, e = block(lines, kind)
    out, depth = lines[:s + 1], 0
    for line in lines[s + 1:e]:
        if line.startswith("BEGIN:"):
            depth += 1
        elif line.startswith("END:"):
            depth -= 1
        name = split_prop(line)[0]
        if depth == 0 and name in changes:
            continue
        out.append(line)
    out += [v for v in changes.values() if v]
    return out + lines[e:]


def serialize(lines):
    return ("\r\n".join(fold(l) for l in lines) + "\r\n").encode()
