#!/usr/bin/env python3
"""Fetch the RSS/Atom feeds from config "news.feeds" and print JSON:
[{name, url, error, items: [{title, link, time (epoch s), summary}]}]
Standard library only. Feeds are fetched in parallel.
"""
import email.utils
import html
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import qsconf

ATOM = "{http://www.w3.org/2005/Atom}"
DC = "{http://purl.org/dc/elements/1.1/}"
RSS1 = "{http://purl.org/rss/1.0/}"


def parse_time(s):
    if not s:
        return 0
    s = s.strip()
    try:
        return int(email.utils.parsedate_to_datetime(s).timestamp())
    except (TypeError, ValueError):
        pass
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return 0


def clean(s, n=240):
    s = re.sub(r"<[^>]+>", " ", html.unescape(s or ""))
    s = re.sub(r"\s+", " ", s).strip()
    return s[:n] + "…" if len(s) > n else s


def text(el, *tags):
    for t in tags:
        c = el.find(t)
        if c is not None and (c.text or "").strip():
            return c.text.strip()
    return ""


def parse(data):
    root = ET.fromstring(data)
    items = []
    if root.tag == ATOM + "feed":
        for e in root.findall(ATOM + "entry"):
            link = ""
            for l in e.findall(ATOM + "link"):
                if l.get("rel", "alternate") == "alternate":
                    link = l.get("href", "")
                    break
            items.append({
                "title": clean(text(e, ATOM + "title"), 300),
                "link": link,
                "time": parse_time(text(e, ATOM + "published", ATOM + "updated")),
                "summary": clean(text(e, ATOM + "summary", ATOM + "content")),
            })
    else:  # RSS 2.0 / RSS 1.0 (RDF)
        for e in root.iter():
            if e.tag not in ("item", RSS1 + "item"):
                continue
            items.append({
                "title": clean(text(e, "title", RSS1 + "title"), 300),
                "link": text(e, "link", RSS1 + "link"),
                "time": parse_time(text(e, "pubDate", DC + "date")),
                "summary": clean(text(e, "description", RSS1 + "description")),
            })
    return items


def fetch(feed, per_feed):
    out = {"name": feed.get("name") or feed["url"], "url": feed["url"],
           "error": "", "items": []}
    try:
        req = urllib.request.Request(feed["url"], headers={"User-Agent": qsconf.UA})
        with urllib.request.urlopen(req, timeout=15) as r:
            items = parse(r.read())
        items.sort(key=lambda i: i["time"], reverse=True)
        out["items"] = items[: feed.get("limit", per_feed)]
    except Exception as e:  # noqa: BLE001 - report any failure per feed
        out["error"] = str(e)[:200]
    return out


def main():
    cfg = qsconf.section("news")
    feeds = [f for f in cfg.get("feeds", []) if f.get("url")]
    per_feed = int(cfg.get("perFeed", 8))
    with ThreadPoolExecutor(max_workers=8) as ex:
        result = list(ex.map(lambda f: fetch(f, per_feed), feeds))
    json.dump(result, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
