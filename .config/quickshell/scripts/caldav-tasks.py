#!/usr/bin/env python3
"""Tasks (VTODO) from a CalDAV task list. Standard library only.

  caldav-tasks.py list                  open tasks as JSON
  caldav-tasks.py complete <href>       mark done (simple recurrences advance)
  caldav-tasks.py reopen <href>         undo "complete"
  caldav-tasks.py add <text>            new task; "@today", "@tomorrow", "@mon",
                                        "@+3", "@2026-11-03" set the due date,
                                        a lone "!" makes it high priority
  caldav-tasks.py calendars             list the task lists found on the server

Config "tasks": {url, calendar}; credentials "tasks": {username, password} or
{username, passwordCommand} belong in ~/.local/share/quickshell/private.json.
"""
import base64
import calendar
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import qsconf

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "cs": "http://calendarserver.org/ns/"}
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "quickshell", "caldav.json")


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
                'xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">'
                f'<d:prop>{props}</d:prop></d:propfind>').encode()
        _, _, data = self.request("PROPFIND", url, body, depth=depth)
        return ET.fromstring(data)


def href_of(resp, base):
    return urllib.parse.urljoin(base, resp.findtext("d:href", "", NS))


# ---- discovery ----------------------------------------------------------------------
def task_lists(cli, url):
    root = cli.propfind(url, "<d:current-user-principal/>")
    p = root.find(".//d:current-user-principal/d:href", NS)
    principal = urllib.parse.urljoin(url, p.text) if p is not None else url
    root = cli.propfind(principal, "<c:calendar-home-set/>")
    h = root.find(".//c:calendar-home-set/d:href", NS)
    home = urllib.parse.urljoin(principal, h.text) if h is not None else principal
    root = cli.propfind(home, "<d:displayname/><d:resourcetype/><c:supported-calendar-component-set/>", 1)
    out = []
    for r in root.findall("d:response", NS):
        if r.find(".//d:resourcetype/c:calendar", NS) is None:
            continue
        comps = [c.get("name") for c in r.findall(".//c:supported-calendar-component-set/c:comp", NS)]
        href = href_of(r, home)
        name = r.findtext(".//d:displayname", "", NS) or href.rstrip("/").rsplit("/", 1)[-1]
        out.append({"href": href, "name": name, "todo": not comps or "VTODO" in comps})
    return out


def collection(cli, cfg, refresh=False):
    url, want = cfg.get("url", ""), cfg.get("calendar", "Tasks")
    if not url:
        raise Fail("tasks.url is not set")
    key = f"{url}|{want}"
    try:
        with open(CACHE) as f:
            cached = json.load(f)
        if not refresh and cached.get("key") == key:
            return cached["href"]
    except (OSError, ValueError):
        pass
    lists = task_lists(cli, url)
    match = [l for l in lists if l["name"].lower() == want.lower()] or \
            [l for l in lists if l["href"].rstrip("/").rsplit("/", 1)[-1].lower() == want.lower()]
    if not match:
        raise Fail(f"no task list named '{want}' (found: {', '.join(l['name'] for l in lists)})")
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w") as f:
        json.dump({"key": key, "href": match[0]["href"]}, f)
    return match[0]["href"]


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


def epoch_ms(d):
    if isinstance(d, datetime):
        return int(d.timestamp() * 1000)
    return int(datetime(d.year, d.month, d.day).astimezone().timestamp() * 1000)


def todo_block(lines):
    try:
        s = lines.index("BEGIN:VTODO")
        return s, lines.index("END:VTODO", s)
    except ValueError:
        return None, None


def parse_todo(text, href, etag):
    lines = unfold(text)
    s, e = todo_block(lines)
    if s is None:
        return None
    t = {"href": href, "etag": etag, "uid": "", "summary": "", "description": "", "status": "",
         "priority": 0, "due": 0, "allDay": False, "start": 0, "parent": "", "recurring": False,
         "categories": []}
    depth = 0
    for line in lines[s + 1:e]:
        if line.startswith("BEGIN:"):
            depth += 1                       # skip VALARM etc.
        elif line.startswith("END:"):
            depth -= 1
        if depth:
            continue
        name, params, value = split_prop(line)
        if name == "UID":
            t["uid"] = value
        elif name == "SUMMARY":
            t["summary"] = unescape(value)
        elif name == "DESCRIPTION":
            t["description"] = unescape(value)[:500]
        elif name == "STATUS":
            t["status"] = value.upper()
        elif name == "PRIORITY":
            t["priority"] = int(value or 0)
        elif name == "DUE":
            d, t["allDay"] = parse_dt(value, params)
            t["due"] = epoch_ms(d)
        elif name == "DTSTART":
            t["start"] = epoch_ms(parse_dt(value, params)[0])
        elif name == "RELATED-TO" and params.get("RELTYPE", "PARENT") == "PARENT":
            t["parent"] = value
        elif name == "RRULE":
            t["recurring"] = True
        elif name == "CATEGORIES":
            t["categories"] = [unescape(c) for c in re.split(r"(?<!\\),", value) if c]
        elif name == "COMPLETED":
            t["status"] = t["status"] or "COMPLETED"
    return t


def utcstamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def set_props(lines, changes):
    """changes: {NAME: full line or None (remove)} inside the VTODO block"""
    s, e = todo_block(lines)
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


def advance(lines, rrule):
    """simple recurrence (FREQ + INTERVAL): move DUE/DTSTART to the next date"""
    parts = dict(p.split("=", 1) for p in rrule.split(";") if "=" in p)
    if set(parts) - {"FREQ", "INTERVAL", "WKST"}:
        raise Fail("recurring task with a complex rule: complete it in your task app")
    n = int(parts.get("INTERVAL", 1))
    freq = parts.get("FREQ")
    changes = {}
    s, e = todo_block(lines)
    for line in lines[s + 1:e]:
        name, params, value = split_prop(line)
        if name not in ("DUE", "DTSTART"):
            continue
        d, all_day = parse_dt(value, params)
        if freq == "DAILY":
            d += timedelta(days=n)
        elif freq == "WEEKLY":
            d += timedelta(weeks=n)
        elif freq in ("MONTHLY", "YEARLY"):
            months = n if freq == "MONTHLY" else 12 * n
            y, m = divmod(d.month - 1 + months, 12)
            last = calendar.monthrange(d.year + y, m + 1)[1]
            d = d.replace(year=d.year + y, month=m + 1, day=min(d.day, last))
        else:
            raise Fail(f"recurring task (FREQ={freq}): complete it in your task app")
        head = line.split(":", 1)[0]
        if all_day:
            changes[name] = f"{head}:{d.strftime('%Y%m%d')}"
        elif value.endswith("Z"):
            changes[name] = f"{head}:{d.astimezone(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
        else:
            changes[name] = f"{head}:{d.strftime('%Y%m%dT%H%M%S')}"
    return changes


# ---- commands ---------------------------------------------------------------------------
REPORT = b"""<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VTODO"/></c:comp-filter></c:filter>
</c:calendar-query>"""


def cmd_list(cli, cfg):
    try:
        coll = collection(cli, cfg)
        _, _, data = cli.request("REPORT", coll, REPORT, depth=1)
    except Fail:
        coll = collection(cli, cfg, refresh=True)     # cached URL may be stale
        _, _, data = cli.request("REPORT", coll, REPORT, depth=1)
    tasks = []
    for r in ET.fromstring(data).findall("d:response", NS):
        cal = r.findtext(".//c:calendar-data", "", NS)
        t = parse_todo(cal, href_of(r, coll), r.findtext(".//d:getetag", "", NS))
        if t and t["status"] not in ("COMPLETED", "CANCELLED"):
            tasks.append(t)
    big = 1 << 62
    tasks.sort(key=lambda t: (t["due"] or big, t["priority"] or 10, t["summary"].lower()))
    return {"tasks": tasks, "list": cfg.get("calendar", "Tasks")}


def modify(cli, href, fn):
    _, headers, data = cli.request("GET", href)
    etag = {k.lower(): v for k, v in headers.items()}.get("etag")
    lines = unfold(data.decode("utf-8"))
    if lines and lines[-1] == "":
        lines.pop()
    lines = fn(lines)
    body = ("\r\n".join(fold(l) for l in lines) + "\r\n").encode()
    cli.request("PUT", href, body, headers={"If-Match": etag} if etag else {})


def cmd_complete(cli, cfg, href):
    def fn(lines):
        s, e = todo_block(lines)
        rrule = next((split_prop(l)[2] for l in lines[s:e] if l.startswith("RRULE")), None)
        now = utcstamp()
        if rrule:
            changes = advance(lines, rrule)
            changes.update({"LAST-MODIFIED": f"LAST-MODIFIED:{now}", "DTSTAMP": f"DTSTAMP:{now}"})
            return set_props(lines, changes)
        return set_props(lines, {"STATUS": "STATUS:COMPLETED", "COMPLETED": f"COMPLETED:{now}",
                                 "PERCENT-COMPLETE": "PERCENT-COMPLETE:100",
                                 "LAST-MODIFIED": f"LAST-MODIFIED:{now}", "DTSTAMP": f"DTSTAMP:{now}"})
    modify(cli, href, fn)
    return {"ok": True}


def cmd_reopen(cli, cfg, href):
    now = utcstamp()
    modify(cli, href, lambda lines: set_props(lines, {
        "STATUS": "STATUS:NEEDS-ACTION", "COMPLETED": None, "PERCENT-COMPLETE": None,
        "LAST-MODIFIED": f"LAST-MODIFIED:{now}", "DTSTAMP": f"DTSTAMP:{now}"}))
    return {"ok": True}


WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def parse_quick(text):
    due, prio, words = None, 0, []
    today = date.today()
    for w in text.split():
        lw = w.lower()
        if lw.startswith("@") and len(lw) > 1:
            v = lw[1:]
            if v in ("today", "heute"):
                due = today
            elif v in ("tomorrow", "morgen"):
                due = today + timedelta(days=1)
            elif v[:3] in WEEKDAYS:
                due = today + timedelta(days=(WEEKDAYS.index(v[:3]) - today.weekday() - 1) % 7 + 1)
            elif re.fullmatch(r"\+\d+", v):
                due = today + timedelta(days=int(v[1:]))
            elif re.fullmatch(r"\d{4}-\d{2}-\d{2}", v):
                due = date.fromisoformat(v)
            else:
                words.append(w)
        elif w == "!":
            prio = 1
        else:
            words.append(w)
    return " ".join(words), due, prio


def cmd_add(cli, cfg, text):
    summary, due, prio = parse_quick(text)
    if not summary:
        raise Fail("empty task")
    uid = str(uuid.uuid4())
    now = utcstamp()
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell//dashboard//EN",
             "BEGIN:VTODO", f"UID:{uid}", f"DTSTAMP:{now}", f"CREATED:{now}",
             f"LAST-MODIFIED:{now}", f"SUMMARY:{escape(summary)}", "STATUS:NEEDS-ACTION"]
    if due:
        lines.append(f"DUE;VALUE=DATE:{due.strftime('%Y%m%d')}")
    if prio:
        lines.append(f"PRIORITY:{prio}")
    lines += ["END:VTODO", "END:VCALENDAR"]
    body = ("\r\n".join(fold(l) for l in lines) + "\r\n").encode()
    href = urllib.parse.urljoin(collection(cli, cfg), uid + ".ics")
    cli.request("PUT", href, body, headers={"If-None-Match": "*"})
    return {"ok": True, "href": href}


def main():
    cfg = qsconf.section("tasks")
    args = sys.argv[1:] or ["list"]
    try:
        cli = Client(cfg)
        cmd = args[0]
        if cmd == "list":
            out = cmd_list(cli, cfg)
        elif cmd == "calendars":
            out = {"calendars": task_lists(cli, cfg.get("url", ""))}
        elif cmd == "complete" and len(args) > 1:
            out = cmd_complete(cli, cfg, args[1])
        elif cmd == "reopen" and len(args) > 1:
            out = cmd_reopen(cli, cfg, args[1])
        elif cmd == "add" and len(args) > 1:
            out = cmd_add(cli, cfg, " ".join(args[1:]))
        else:
            raise Fail(__doc__)
    except Fail as e:
        out = {"error": str(e)}
    except Exception as e:  # noqa: BLE001
        out = {"error": f"{type(e).__name__}: {e}"}
    json.dump(out, sys.stdout, ensure_ascii=False)
    sys.exit(1 if "error" in out else 0)


if __name__ == "__main__":
    main()
