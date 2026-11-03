#!/usr/bin/env python3
"""Calendar events (VEVENT) of CalDAV calendars. Standard library only.

  caldav-events.py list [YYYY-MM-DD] [days]   events from that day (default:
                                              today) for `days` days (default 28)
  caldav-events.py calendars                  calendars found on the server
  caldav-events.py create <json>              new event: {calendar, summary,
                                              location, description, allDay,
                                              start, end}
  caldav-events.py update <href> <json>       change an event (not recurring)
  caldav-events.py delete <href>              delete; prints the old iCalendar
  caldav-events.py restore <href> <ics>       put a deleted event back (undo)

Write input: all-day start/end "YYYY-MM-DD" (end exclusive), timed
"YYYY-MM-DDTHH:MM" local time. Updates keep the event's TZID (else UTC).

The server expands recurring events (CalDAV <expand>); a second, raw query
tells which ones are all-day (expansion turns dates into UTC date-times).

Config "calendar": {url, calendars[], exclude[], colors{name: "#rrggbb"}};
url and credentials default to the "tasks" section (same server).
Output: {"events": [{uid, href, etag, summary, location, description, url,
calendar, color, allDay, recurring, start, end}], "calendars": [{name, color}]}. Timed events have
start/end in epoch ms; all-day events "YYYY-MM-DD" with an exclusive end.
"""
import json
import sys
import urllib.parse
import uuid
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import qsconf
from caldav import (NS, Client, Fail, block, cached_calendars, components, escape, href_of,
                    parse_dt, parse_duration, serialize, set_props, split_prop, unescape,
                    unfold, utcstamp)

# distinct colours when the server gives every calendar the same one
PALETTE = ["#5e9cf0", "#e0a43a", "#5fbf77", "#d1607a", "#9b7be0", "#4fc1c1", "#c9864f"]


def config():
    tasks = qsconf.section("tasks")
    cal = qsconf.section("calendar")
    cfg = {k: tasks[k] for k in ("url", "username", "password", "passwordCommand") if k in tasks}
    cfg.update(cal)
    if "exclude" not in cal and tasks.get("calendar"):
        cfg["exclude"] = [tasks["calendar"]]    # the task list holds no events
    return cfg


def selected(cli, cfg, refresh=False):
    url = cfg.get("url", "")
    if not url:
        raise Fail("calendar.url (or tasks.url) is not set")
    cals = [c for c in cached_calendars(cli, url, refresh) if c["event"]]
    want = [n.lower() for n in cfg.get("calendars", [])]
    skip = [n.lower() for n in cfg.get("exclude", [])]
    if want:
        cals = [c for c in cals if c["name"].lower() in want]
    cals = [c for c in cals if c["name"].lower() not in skip]
    # colours: config, else the server's if they differ, else a palette
    overrides = cfg.get("colors", {})
    distinct = len({c["color"].lower() for c in cals}) == len(cals)
    for i, c in enumerate(cals):
        c["color"] = overrides.get(c["name"]) or (c["color"] if distinct and c["color"] else
                                                  PALETTE[i % len(PALETTE)])
    return cals


def query(start, end, expand):
    s, e = (d.strftime("%Y%m%dT%H%M%SZ") for d in (start, end))
    exp = f'<c:expand start="{s}" end="{e}"/>' if expand else ""
    return f"""<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data>{exp}</c:calendar-data></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
    <c:time-range start="{s}" end="{e}"/>
  </c:comp-filter></c:comp-filter></c:filter>
</c:calendar-query>""".encode()


def report(cli, href, start, end, expand):
    """-> (object href, etag, [VEVENT property lines, ...]) per calendar object"""
    _, _, data = cli.request("REPORT", href, query(start, end, expand), depth=1)
    for r in ET.fromstring(data).findall("d:response", NS):
        yield (href_of(r, href), r.findtext(".//d:getetag", "", NS),
               components(unfold(r.findtext(".//c:calendar-data", "", NS)), "VEVENT"))


def to_date(d):
    """all-day value as returned by the expansion (UTC midnight) -> date"""
    if isinstance(d, datetime):
        d = d.astimezone(timezone.utc)
        return (d + timedelta(hours=12)).date()     # tolerate servers using local midnight
    return d


def events_of(cli, cal, start, end):
    # raw objects: which UIDs are all-day / recurring, and where they live
    meta = {}
    for href, etag, vevents in report(cli, cal["href"], start, end, expand=False):
        for props in vevents:
            uid, day, rec = "", False, len(vevents) > 1
            for line in props:
                name, params, value = split_prop(line)
                if name == "UID":
                    uid = value
                elif name == "DTSTART":
                    day = parse_dt(value, params)[1]
                elif name in ("RRULE", "RDATE", "RECURRENCE-ID"):
                    rec = True
            m = meta.setdefault(uid, {"allDay": False, "recurring": False, "href": href, "etag": etag})
            m["allDay"] |= day
            m["recurring"] |= rec

    out = []
    occurrences = [(href, props) for href, _, vevents in report(cli, cal["href"], start, end, expand=True)
                   for props in vevents]
    for href, props in occurrences:
        ev = {"uid": "", "summary": "", "location": "", "description": "", "url": "", "status": ""}
        dtstart = dtend = duration = None
        for line in props:
            name, params, value = split_prop(line)
            if name == "UID":
                ev["uid"] = value
            elif name == "SUMMARY":
                ev["summary"] = unescape(value)
            elif name == "LOCATION":
                ev["location"] = unescape(value)
            elif name == "DESCRIPTION":
                ev["description"] = unescape(value).strip()[:500]
            elif name == "URL":
                ev["url"] = value
            elif name == "STATUS":
                ev["status"] = value.upper()
            elif name == "DTSTART":
                dtstart = parse_dt(value, params)[0]
            elif name == "DTEND":
                dtend = parse_dt(value, params)[0]
            elif name == "DURATION":
                duration = parse_duration(value)
        if dtstart is None or ev["status"] == "CANCELLED":
            continue
        if dtend is None:
            dtend = dtstart + duration if duration is not None else None
        m = meta.get(ev["uid"], {})
        day = m.get("allDay", False) or (isinstance(dtstart, date) and not isinstance(dtstart, datetime))
        ev.pop("status")
        ev.update(calendar=cal["name"], color=cal["color"], allDay=day,
                  recurring=m.get("recurring", False), href=m.get("href", href), etag=m.get("etag", ""))
        if day:
            s = to_date(dtstart)
            e = to_date(dtend) if dtend is not None else s + timedelta(days=1)
            ev["start"], ev["end"] = s.isoformat(), max(e, s + timedelta(days=1)).isoformat()
        else:
            ev["start"] = int(dtstart.timestamp() * 1000)
            ev["end"] = int((dtend or dtstart).timestamp() * 1000)
        out.append(ev)
    return out


def cmd_list(cli, cfg, first, days):
    # local midnight -> UTC range for the query
    start = datetime(first.year, first.month, first.day).astimezone().astimezone(timezone.utc)
    end = start + timedelta(days=days)
    try:
        cals = selected(cli, cfg)
        events = [e for c in cals for e in events_of(cli, c, start, end)]
    except Fail:
        cals = selected(cli, cfg, refresh=True)     # cached calendar URLs may be stale
        events = [e for c in cals for e in events_of(cli, c, start, end)]
    key = lambda e: (e["start"] if e["allDay"] else
                     datetime.fromtimestamp(e["start"] / 1000).date().isoformat(),
                     not e["allDay"], str(e["start"]), e["summary"].lower())
    events.sort(key=key)
    return {"events": events, "from": first.isoformat(), "days": days,
            "calendars": [{"name": c["name"], "color": c["color"]} for c in cals]}


# ---- writing ------------------------------------------------------------------------
def dt_lines(data, tzid=None):
    """{allDay, start, end} -> DTSTART / DTEND property lines"""
    if data.get("allDay"):
        s = date.fromisoformat(data["start"][:10])
        e = date.fromisoformat(data["end"][:10]) if data.get("end") else s + timedelta(days=1)
        e = max(e, s + timedelta(days=1))
        return f"DTSTART;VALUE=DATE:{s:%Y%m%d}", f"DTEND;VALUE=DATE:{e:%Y%m%d}"
    s = datetime.fromisoformat(data["start"]).astimezone()      # naive = local time
    e = datetime.fromisoformat(data["end"]).astimezone() if data.get("end") else s + timedelta(hours=1)
    if e < s:
        raise Fail("the event ends before it starts")
    try:
        zone = ZoneInfo(tzid) if tzid else None
    except Exception:  # noqa: BLE001 - unknown TZID: write UTC
        zone = None
    if zone:
        return (f"DTSTART;TZID={tzid}:{s.astimezone(zone):%Y%m%dT%H%M%S}",
                f"DTEND;TZID={tzid}:{e.astimezone(zone):%Y%m%dT%H%M%S}")
    utc = timezone.utc
    return f"DTSTART:{s.astimezone(utc):%Y%m%dT%H%M%SZ}", f"DTEND:{e.astimezone(utc):%Y%m%dT%H%M%SZ}"


def text_line(name, value):
    value = (value or "").strip()
    return f"{name}:{escape(value)}" if value else None


def cmd_create(cli, cfg, data):
    if not (data.get("summary") or "").strip():
        raise Fail("the event needs a title")
    cals = selected(cli, cfg)
    want = (data.get("calendar") or cfg.get("defaultCalendar") or "").lower()
    cal = next((c for c in cals if c["name"].lower() == want), cals[0] if cals else None)
    if cal is None:
        raise Fail("no calendar to write to")
    uid, now = str(uuid.uuid4()), utcstamp()
    start, end = dt_lines(data)
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell//dashboard//EN", "BEGIN:VEVENT",
             f"UID:{uid}", f"DTSTAMP:{now}", f"CREATED:{now}", f"LAST-MODIFIED:{now}", "SEQUENCE:0",
             text_line("SUMMARY", data["summary"]), start, end,
             text_line("LOCATION", data.get("location")), text_line("DESCRIPTION", data.get("description")),
             "END:VEVENT", "END:VCALENDAR"]
    href = urllib.parse.urljoin(cal["href"], uid + ".ics")
    cli.request("PUT", href, serialize([l for l in lines if l]), headers={"If-None-Match": "*"})
    return {"ok": True, "href": href, "uid": uid}


def fetch(cli, href):
    _, headers, data = cli.request("GET", href)
    etag = {k.lower(): v for k, v in headers.items()}.get("etag")
    lines = unfold(data.decode("utf-8"))
    while lines and lines[-1] == "":
        lines.pop()
    return lines, etag, data.decode("utf-8")


def cmd_update(cli, href, data):
    if not (data.get("summary") or "").strip():
        raise Fail("the event needs a title")
    lines, etag, _ = fetch(cli, href)
    vevents = components(lines, "VEVENT")
    if len(vevents) != 1 or any(split_prop(l)[0] in ("RRULE", "RDATE", "RECURRENCE-ID") for l in vevents[0]):
        raise Fail("recurring event: change it in your calendar app")
    tzid, seq = None, 0
    for line in vevents[0]:
        name, params, value = split_prop(line)
        if name == "DTSTART":
            tzid = params.get("TZID")
        elif name == "SEQUENCE" and value.strip().isdigit():
            seq = int(value)
    start, end = dt_lines(data, tzid)
    now = utcstamp()
    lines = set_props(lines, {
        "SUMMARY": text_line("SUMMARY", data["summary"]),
        "LOCATION": text_line("LOCATION", data.get("location")),
        "DESCRIPTION": text_line("DESCRIPTION", data.get("description")),
        "DTSTART": start, "DTEND": end, "DURATION": None,
        "SEQUENCE": f"SEQUENCE:{seq + 1}", "LAST-MODIFIED": f"LAST-MODIFIED:{now}", "DTSTAMP": f"DTSTAMP:{now}",
    }, "VEVENT")
    cli.request("PUT", href, serialize(lines), headers={"If-Match": etag} if etag else {})
    return {"ok": True, "href": href}


def cmd_delete(cli, href):
    lines, etag, raw = fetch(cli, href)
    if block(lines, "VEVENT")[0] is None:
        raise Fail("not an event")
    cli.request("DELETE", href, headers={"If-Match": etag} if etag else {})
    return {"ok": True, "href": href, "ics": raw}


def cmd_restore(cli, href, ics):
    if "BEGIN:VEVENT" not in ics:
        raise Fail("nothing to restore")
    cli.request("PUT", href, ics.encode(), headers={"If-None-Match": "*",
                                                    "Content-Type": "text/calendar; charset=utf-8"})
    return {"ok": True, "href": href}


def main():
    cfg = config()
    args = sys.argv[1:] or ["list"]
    try:
        cli = Client(cfg)
        if args[0] == "list":
            first = date.fromisoformat(args[1]) if len(args) > 1 else date.today()
            days = max(1, min(int(args[2]) if len(args) > 2 else 28, 400))
            out = cmd_list(cli, cfg, first, days)
        elif args[0] == "calendars":
            out = {"calendars": selected(cli, cfg, refresh=True)}
        elif args[0] == "create" and len(args) > 1:
            out = cmd_create(cli, cfg, json.loads(args[1]))
        elif args[0] == "update" and len(args) > 2:
            out = cmd_update(cli, args[1], json.loads(args[2]))
        elif args[0] == "delete" and len(args) > 1:
            out = cmd_delete(cli, args[1])
        elif args[0] == "restore" and len(args) > 2:
            out = cmd_restore(cli, args[1], args[2])
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
