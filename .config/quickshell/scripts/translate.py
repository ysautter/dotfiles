#!/usr/bin/env python3
"""Translate stdin. Prints JSON {text, detected, backend} or {error}.

  translate.py --to de [--from auto] [--backend mymemory|libretranslate|deepl|pi] [-- text]

Backends (config "translate"):
  mymemory        free web API, no key (optional "email" raises the daily quota)
  libretranslate  self-hosted: translate.libretranslate.url (+ apiKey)
  deepl           translate.deepl.apiKey (free keys end in ":fx")
  pi              the pi agent (LLM), translate.pi.model
"""
import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

import qsconf

NAMES = {"de": "German", "en": "English", "fr": "French", "es": "Spanish", "it": "Italian",
         "nl": "Dutch", "pl": "Polish", "pt": "Portuguese", "ru": "Russian", "uk": "Ukrainian",
         "tr": "Turkish", "sv": "Swedish", "da": "Danish", "no": "Norwegian", "fi": "Finnish",
         "cs": "Czech", "ja": "Japanese", "zh": "Chinese", "ko": "Korean", "ar": "Arabic"}


class Fail(Exception):
    pass


def http(url, data=None, headers=None, timeout=20):
    h = {"User-Agent": qsconf.UA}
    h.update(headers or {})
    if isinstance(data, (dict, list)):
        data = json.dumps(data).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise Fail(f"HTTP {e.code}: {e.read()[:200].decode(errors='replace')}") from None
    except urllib.error.URLError as e:
        raise Fail(str(e.reason)) from None


def chunks(text, limit=450):
    """split at paragraph/sentence boundaries into pieces of <= limit bytes"""
    out, cur = [], ""
    for part in re.split(r"(?<=[.!?\n])\s+", text):
        while len(part.encode()) > limit:            # very long sentence: hard split
            cut = limit
            while len(part[:cut].encode()) > limit:
                cut -= 10
            out.append(part[:cut])
            part = part[cut:]
        if len((cur + " " + part).encode()) > limit and cur:
            out.append(cur)
            cur = part
        else:
            cur = (cur + " " + part).strip() if cur else part
    if cur:
        out.append(cur)
    return out


def mymemory(text, src, tgt, cfg):
    res, detected = [], ""
    for piece in chunks(text):
        q = {"q": piece, "langpair": f"{'autodetect' if src == 'auto' else src}|{tgt}"}
        if cfg.get("email"):
            q["de"] = cfg["email"]
        j = http("https://api.mymemory.translated.net/get?" + urllib.parse.urlencode(q))
        if j.get("responseStatus") not in (200, "200"):
            raise Fail(j.get("responseDetails") or "MyMemory error")
        res.append(j["responseData"]["translatedText"])
        detected = detected or j["responseData"].get("detectedLanguage") or ""
    return " ".join(res), detected


def libretranslate(text, src, tgt, cfg):
    c = cfg.get("libretranslate", {})
    if not c.get("url"):
        raise Fail("translate.libretranslate.url is not set")
    body = {"q": text, "source": src, "target": tgt, "format": "text"}
    if c.get("apiKey"):
        body["api_key"] = c["apiKey"]
    j = http(c["url"].rstrip("/") + "/translate", body)
    if "error" in j:
        raise Fail(j["error"])
    return j["translatedText"], (j.get("detectedLanguage") or {}).get("language", "")


def deepl(text, src, tgt, cfg):
    key = cfg.get("deepl", {}).get("apiKey")
    if not key:
        raise Fail("translate.deepl.apiKey is not set (private.json)")
    host = "api-free.deepl.com" if key.endswith(":fx") else "api.deepl.com"
    target = {"en": "EN-GB", "pt": "PT-PT"}.get(tgt, tgt.upper())
    body = {"text": [text], "target_lang": target}
    if src != "auto":
        body["source_lang"] = src.upper()
    j = http(f"https://{host}/v2/translate", body, {"Authorization": f"DeepL-Auth-Key {key}"})
    t = j["translations"][0]
    return t["text"], t.get("detected_source_language", "").lower()


def pi(text, src, tgt, cfg):
    model = cfg.get("pi", {}).get("model", "")
    lang = NAMES.get(tgt, tgt)
    system = (f"You are a translation engine. Translate the user's text into {lang}"
              + (f" from {NAMES.get(src, src)}" if src != "auto" else "")
              + ". Keep meaning, tone and formatting. Output only the translation, nothing else.")
    cmd = ["pi", "-p", "--no-session", "--no-tools", "--no-context-files", "--no-skills",
           "--no-prompt-templates", "--no-mcp", "--system-prompt", system]
    if model:
        cmd += ["--model", model]
    r = subprocess.run(cmd + [text], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise Fail((r.stderr or r.stdout).strip()[:300] or "pi failed")
    return r.stdout.strip(), ""


BACKENDS = {"mymemory": mymemory, "libretranslate": libretranslate, "deepl": deepl, "pi": pi}


def main():
    cfg = qsconf.section("translate")
    ap = argparse.ArgumentParser()
    ap.add_argument("--to", default=cfg.get("target", "en"))
    ap.add_argument("--from", dest="src", default="auto")
    ap.add_argument("--backend", default=cfg.get("backend", "mymemory"))
    ap.add_argument("text", nargs="?", help="text (default: stdin)")
    a = ap.parse_args()
    text = (a.text if a.text is not None else sys.stdin.read()).strip()
    try:
        if a.backend not in BACKENDS:
            raise Fail(f"unknown backend {a.backend}")
        out, detected = BACKENDS[a.backend](text, a.src, a.to, cfg) if text else ("", "")
        res = {"text": out, "detected": (detected or "").split("-")[0].lower(), "backend": a.backend}
    except Fail as e:
        res = {"error": str(e)}
    except Exception as e:  # noqa: BLE001
        res = {"error": f"{type(e).__name__}: {e}"}
    json.dump(res, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
