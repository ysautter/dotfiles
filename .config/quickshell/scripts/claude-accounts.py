#!/usr/bin/env python3
"""Claude subscription usage (5 h session + 7 d weekly) for every Anthropic
account saved by the pi `anthropic-accounts` extension.

Accounts come from ~/.pi/agent/anthropic-accounts.json; the *active* one's
live credential is in ~/.pi/agent/auth.json (pi refreshes it there), the
others are parked in the store. Expired tokens are renewed with the refresh
token (same OAuth client as pi / Claude Code) and written back atomically
under pi's `auth.json.lock`, which the extension also uses when switching.

Prints JSON: {"active": name, "accounts": [{name, email, active, sessionPct,
sessionReset, sessionResetAt, weeklyPct, weeklyReset, weeklyResetAt, error}]}
"""

import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

AGENT = Path(os.environ.get("PI_CODING_AGENT_DIR", Path.home() / ".pi/agent"))
AUTH_FILE = AGENT / "auth.json"
STORE_FILE = AGENT / "anthropic-accounts.json"
LOCK = Path(str(AUTH_FILE) + ".lock")
STATE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "claude-usage"

PROVIDER = "anthropic"
TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
UA = "claude-code/2.0.0"
COOLDOWN = 900  # s to wait after a failed refresh (endpoint rate-limits)


def now_ms():
    return int(time.time() * 1000)


def read_json(path, fallback):
    try:
        return json.loads(path.read_text(encoding="utf-8").lstrip("\ufeff"))
    except Exception:
        return fallback


def write_secret(path, data):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


class AuthLock:
    """mkdir lock compatible with pi's proper-lockfile on auth.json."""

    def __enter__(self):
        deadline = time.time() + 10
        while True:
            try:
                LOCK.mkdir()
                return self
            except FileExistsError:
                try:
                    if time.time() - LOCK.stat().st_mtime > 30:
                        LOCK.rmdir()
                        continue
                except OSError:
                    pass
                if time.time() > deadline:
                    raise TimeoutError("auth.json is locked")
                time.sleep(0.05)

    def __exit__(self, *exc):
        try:
            LOCK.rmdir()
        except OSError:
            pass


def post_json(url, body):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def credential_of(name, store, auth):
    if name == store.get("active") and isinstance(auth.get(PROVIDER), dict):
        return auth[PROVIDER]
    return (store.get("accounts", {}).get(name) or {}).get("credential") or {}


def refresh(name, force=False):
    """Renew `name`'s token; returns the (possibly new) credential or None."""
    fail = STATE / f"refresh-failed-{name}"
    with AuthLock():
        # Re-read under the lock: pi or a switch may have changed things.
        store = read_json(STORE_FILE, {"accounts": {}})
        auth = read_json(AUTH_FILE, {})
        cred = credential_of(name, store, auth)
        if not force and cred.get("expires", 0) > now_ms() + 60_000:
            return cred
        if fail.exists() and time.time() - fail.stat().st_mtime < COOLDOWN:
            return None
        if not cred.get("refresh"):
            return None
        try:
            r = post_json(TOKEN_URL, {"grant_type": "refresh_token",
                                      "client_id": CLIENT_ID,
                                      "refresh_token": cred["refresh"]})
            if not r.get("access_token"):
                raise ValueError("no access_token in reply")
        except Exception as e:
            body = ""
            if isinstance(e, urllib.error.HTTPError):
                body = e.read()[:300].decode(errors="replace")
            with open(STATE / "refresh-error.log", "a") as log:
                log.write(f"{datetime.now().isoformat()} [{name}] {e} {body}\n")
            fail.touch()
            return None
        new = {**cred, "type": "oauth", "access": r["access_token"],
               "refresh": r.get("refresh_token") or cred["refresh"],
               "expires": now_ms() + int(r.get("expires_in", 3600)) * 1000 - 5 * 60 * 1000}
        # Refresh tokens rotate: persist where pi / the extension will look.
        if name == store.get("active"):
            auth[PROVIDER] = new
            write_secret(AUTH_FILE, auth)
        store["accounts"][name]["credential"] = new
        write_secret(STORE_FILE, store)
        fail.unlink(missing_ok=True)
        return new


def fetch_usage(token):
    req = urllib.request.Request(USAGE_URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def fmt(iso, pattern):
    if not iso:
        return ""
    try:
        return datetime.fromisoformat(iso).astimezone().strftime(pattern)
    except ValueError:
        return ""


def account(name, store, auth):
    meta = store["accounts"][name] or {}
    out = {"name": name, "email": meta.get("email", ""),
           "active": name == store.get("active"),
           "sessionPct": -1, "sessionReset": "", "sessionResetAt": "",
           "weeklyPct": -1, "weeklyReset": "", "weeklyResetAt": "", "error": ""}
    cred = credential_of(name, store, auth)
    if cred.get("type") != "oauth" or not cred.get("access"):
        out["error"] = "no OAuth credential"
        return out
    if cred.get("expires", 0) < now_ms() + 60_000:
        cred = refresh(name)
        if not cred:
            out["error"] = "token expired, refresh failed – log in again in pi"
            return out
    try:
        try:
            u = fetch_usage(cred["access"])
        except urllib.error.HTTPError as e:
            if e.code != 401:
                raise
            cred = refresh(name, force=True)  # rejected although not expired
            if not cred:
                out["error"] = "token rejected, refresh failed – log in again in pi"
                return out
            u = fetch_usage(cred["access"])
    except urllib.error.HTTPError as e:
        out["error"] = f"HTTP {e.code}"
        return out
    except Exception as e:
        out["error"] = f"network error ({e.__class__.__name__})"
        return out
    s, w = u.get("five_hour") or {}, u.get("seven_day") or {}
    out.update(
        sessionPct=int(s.get("utilization") or 0),
        sessionResetAt=s.get("resets_at") or "",
        sessionReset=fmt(s.get("resets_at"), "%H:%M"),
        weeklyPct=int(w.get("utilization") or 0),
        weeklyResetAt=w.get("resets_at") or "",
        weeklyReset=fmt(w.get("resets_at"), "%a %d.%m %H:%M"))
    return out


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    store = read_json(STORE_FILE, {"accounts": {}})
    if not isinstance(store.get("accounts"), dict):
        store["accounts"] = {}
    auth = read_json(AUTH_FILE, {})
    names = list(store["accounts"])
    if not names:
        print(json.dumps({"active": "", "accounts": [],
                          "error": f"no accounts in {STORE_FILE}"}))
        return
    with ThreadPoolExecutor(len(names)) as ex:
        accounts = list(ex.map(lambda n: account(n, store, auth), names))
    print(json.dumps({"active": store.get("active") or "", "accounts": accounts}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({"active": "", "accounts": [], "error": str(e)}))
        sys.exit(0)
