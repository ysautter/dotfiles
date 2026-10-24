"""Shared config loader for the dashboard scripts.

config/dashboard.json (in the dotfiles repo) deep-merged with
~/.local/share/quickshell/private.json (credentials, holdings, API keys;
never committed).
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PUBLIC = os.path.join(HERE, "..", "config", "dashboard.json")
PRIVATE = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
    "quickshell", "private.json")


def _merge(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            out[k] = _merge(a.get(k), v) if k in a else v
        return out
    return b


def lenient(text):
    """JSON with // comments and trailing commas (hand-edited files)"""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1:i + 2])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif c in "}]":
            while out and out[-1].isspace():
                out.pop()
            if out and out[-1] == ",":
                out.pop()
            out.append(c)
        else:
            out.append(c)
        i += 1
    return "".join(out)


def _load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.loads(lenient(f.read()))
    except FileNotFoundError:
        return {}
    except ValueError as e:
        raise SystemExit(json.dumps({"error": f"{os.path.basename(path)}: {e}"}))


def load():
    return _merge(_load(PUBLIC), _load(PRIVATE))


def section(name):
    return load().get(name, {}) or {}


UA = "Mozilla/5.0 (X11; Linux x86_64) quickshell-dashboard"
