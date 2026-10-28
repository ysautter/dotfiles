#!/usr/bin/python3
"""Who has what in a GitLab milestone: open issues and merge requests of a
group milestone, split into "in my hands" and "in the hands of others".

Config "gitlab" (dashboard.json / private.json):
  host        GitLab host (e.g. git.groupios.com)
  group       group path (e.g. ems)
  milestone   default milestone title (the panel can override it)
  user        username; default: the authenticated user
  token / tokenCommand   optional; otherwise `glab api` (its auth) is used

Usage:
  gitlab-milestone.py [list] [<milestone>]   -> JSON, see summarize()
  gitlab-milestone.py milestones             -> active group milestones

Who has an item:
  issue          its assignees (none -> "unassigned")
  MR, draft      assignee (or author)                       "draft"
  MR, ready      reviewers who have not reviewed yet        "review"
                 changes requested -> assignee              "changes requested"
                 reviewed/approved -> assignee              "merge"
                 no reviewer -> assignee                    "needs reviewer"
  MRs count when they are in the milestone or target rc/<milestone>.
"""
import json
import subprocess
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import qsconf

CFG = qsconf.section("gitlab")
HOST = CFG.get("host", "")
GROUP = CFG.get("group", "")
_TOKEN = None


def token():
    global _TOKEN
    if _TOKEN is None:
        _TOKEN = CFG.get("token") or ""
        if not _TOKEN and CFG.get("tokenCommand"):
            _TOKEN = subprocess.run(CFG["tokenCommand"], shell=True, capture_output=True,
                                    text=True, timeout=20).stdout.strip()
    return _TOKEN


def api(path):
    if token():
        req = urllib.request.Request(f"https://{HOST}/api/v4/{path}",
                                     headers={"PRIVATE-TOKEN": token(), "User-Agent": qsconf.UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    p = subprocess.run(["glab", "api", "--hostname", HOST, path],
                       capture_output=True, text=True, timeout=60, cwd="/")
    if p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout).strip().splitlines()[-1] if (p.stderr or p.stdout).strip()
                           else f"glab exited with {p.returncode}")
    return json.loads(p.stdout)


def api_all(path):
    out, page = [], 1
    sep = "&" if "?" in path else "?"
    while True:
        chunk = api(f"{path}{sep}per_page=100&page={page}")
        out += chunk
        if len(chunk) < 100 or page >= 20:
            return out
        page += 1


def grp():
    return urllib.parse.quote(GROUP, safe="")


def users(lst):
    return [u["username"] for u in lst or []]


def status_of(labels):
    for l in labels:
        if l.startswith("status:"):
            return l[7:]
    return ""


def base(o, kind):
    return {
        "kind": kind,
        "ref": o["references"]["full"],
        "title": o["title"],
        "url": o["web_url"],
        "updated": o["updated_at"],
        "author": o["author"]["username"],
        "assignees": users(o.get("assignees")),
        "labels": o.get("labels", []),
        "status": status_of(o.get("labels", [])),
        "priority": next((l[9:] for l in o.get("labels", []) if l.startswith("priority:")), ""),
    }


def reviewer_states(mr):
    pid, iid = mr["project_id"], mr["iid"]
    try:
        return {r["user"]["username"]: r.get("state", "unreviewed")
                for r in api(f"projects/{pid}/merge_requests/{iid}/reviewers")}
    except Exception:
        return {u: "unreviewed" for u in users(mr.get("reviewers"))}


def summarize(milestone):
    me = CFG.get("user") or api("user")["username"]
    q = urllib.parse.quote(milestone)
    ms = [m for m in api(f"groups/{grp()}/milestones?title={q}&include_ancestors=true") if m["title"] == milestone]
    issues = api_all(f"groups/{grp()}/issues?milestone={q}&state=opened&scope=all")
    stats = api(f"groups/{grp()}/issues_statistics?milestone={q}&scope=all")["statistics"]["counts"]
    mrs = [m for m in api_all(f"groups/{grp()}/merge_requests?state=opened&scope=all")
           if (m.get("milestone") or {}).get("title") == milestone
           or m["target_branch"] == f"rc/{milestone}"]

    ready = [m for m in mrs if not m["draft"] and m.get("reviewers")]
    with ThreadPoolExecutor(8) as ex:
        states = dict(zip([m["id"] for m in ready], ex.map(reviewer_states, ready)))

    holders = {}            # username -> [item]
    unassigned = []

    def give(user, item):
        holders.setdefault(user, []).append(item)

    for i in issues:
        it = base(i, "issue")
        it["why"] = it["status"] or "open"
        if it["assignees"]:
            for u in it["assignees"]:
                give(u, it)
        else:
            unassigned.append(it)

    for m in mrs:
        it = base(m, "mr")
        it["draft"] = m["draft"]
        it["target"] = m["target_branch"]
        it["mergeStatus"] = m.get("detailed_merge_status", "")
        it["conflict"] = bool(m.get("has_conflicts")) or it["mergeStatus"] == "conflict"
        owners = it["assignees"] or [it["author"]]
        rs = states.get(m["id"], {})
        it["reviewers"] = rs or {u: "unreviewed" for u in users(m.get("reviewers"))}
        if m["draft"]:
            it["why"] = "draft"
            targets = owners
        elif not rs:
            it["why"] = "needs reviewer"
            targets = owners
        else:
            pending = [u for u, s in rs.items() if s in ("unreviewed", "review_started", "unapproved")]
            if any(s == "requested_changes" for s in rs.values()):
                it["why"] = "changes requested"
                targets = owners
            elif pending:
                it["why"] = "review"
                targets = pending
            else:
                it["why"] = "merge"
                targets = owners
        for u in targets:
            give(u, it)

    order = {"review": 0, "changes requested": 1, "merge": 2, "needs reviewer": 3}

    def key(it):
        return (it["kind"] != "issue", order.get(it["why"], 5), it["ref"])

    for lst in holders.values():
        lst.sort(key=key)
    unassigned.sort(key=key)
    mine = holders.pop(me, [])
    others = [{"user": u, "items": holders[u]} for u in sorted(holders, key=lambda u: (-len(holders[u]), u))]
    m0 = ms[0] if ms else {}
    return {
        "user": me,
        "milestone": milestone,
        "found": bool(ms),
        "due": m0.get("due_date"),
        "url": m0.get("web_url", ""),
        "issues": {"all": stats.get("all", 0), "closed": stats.get("closed", 0), "opened": stats.get("opened", 0)},
        "mrCount": len(mrs),
        "mine": mine,
        "unassigned": unassigned,
        "others": others,
    }


def main():
    args = sys.argv[1:]
    cmd = args.pop(0) if args and args[0] in ("list", "milestones") else "list"
    if not HOST or not GROUP:
        print(json.dumps({"error": "gitlab: set host and group in the dashboard config"}))
        return
    try:
        if cmd == "milestones":
            ms = api(f"groups/{grp()}/milestones?state=active&include_ancestors=true")
            ms.sort(key=lambda m: (m.get("due_date") or "9999", m["title"]))
            print(json.dumps({"milestones": [{"title": m["title"], "due": m.get("due_date")} for m in ms]}))
        else:
            milestone = (args[0] if args else "") or CFG.get("milestone", "")
            if not milestone:
                print(json.dumps({"error": "gitlab: no milestone chosen"}))
                return
            print(json.dumps(summarize(milestone)))
    except Exception as e:
        print(json.dumps({"error": f"gitlab: {e}"}))


if __name__ == "__main__":
    main()
