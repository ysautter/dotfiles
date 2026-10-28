#!/usr/bin/env python3
"""Quotes for the watchlist + holdings from config "markets" (Yahoo Finance
chart API, no key). A symbol can be a Yahoo ticker (VWCE.DE, ^GDAXI,
BTC-EUR, EURUSD=X), an ISIN (IE00BK5BQT80) or a WKN (A2PKXG): ISIN/WKN are
mapped to a ticker via OpenFIGI (German listings preferred) and cached.
Cash entries with "actual": "<account>" take their amount from Actual Budget
(scripts/actual.mjs, config "actual", cached for actual.refreshMinutes).
With config "kraken" {apiKey, apiSecret | apiSecretCommand} the Kraken spot
balances (incl. staked/earn) are added: coins as holdings (priced via the
Kraken public OHLC API), fiat as cash; cached for kraken.refreshMinutes.
Prints JSON:
{base, fx: {CUR: rate to base}, quotes: {SYMBOL: {name, price, currency,
 prevClose, change, changePct, spark: [closes], time, ticker}},
 holdings: [auto holdings, e.g. Kraken: {symbol, quantity, name, source, url, cost?}],
 cash: [{name, amount, currency, source}], errors: {SYMBOL: msg}}

  markets.py                 the JSON above
  markets.py resolve <id>    show the ticker an ISIN/WKN resolves to
  markets.py actual          list the Actual Budget accounts + balances
  markets.py kraken          list the Kraken balances
"""
import base64
import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import qsconf

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "quickshell")
SYMBOLS_CACHE = os.path.join(CACHE_DIR, "symbols.json")
ACTUAL_CACHE = os.path.join(CACHE_DIR, "actual.json")
KRAKEN_CACHE = os.path.join(CACHE_DIR, "kraken.json")
HERE = os.path.dirname(os.path.abspath(__file__))

# OpenFIGI exchange code -> Yahoo suffix, in order of preference (EUR first)
EXCHANGES = [("GY", ".DE"), ("GR", ".DE"), ("GF", ".F"), ("GS", ".SG"), ("GM", ".MU"),
             ("GD", ".DU"), ("GH", ".HM"), ("NA", ".AS"), ("FP", ".PA"), ("IM", ".MI"),
             ("SW", ".SW"), ("LN", ".L"), ("US", ""), ("UN", ""), ("UW", ""), ("UQ", "")]

URL = "https://query1.finance.yahoo.com/v8/finance/chart/{}?range=1mo&interval=1d"


def quote(symbol):
    req = urllib.request.Request(URL.format(urllib.parse.quote(symbol)),
                                 headers={"User-Agent": qsconf.UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        j = json.load(r)
    res = (j.get("chart", {}).get("result") or [None])[0]
    if not res:
        err = j.get("chart", {}).get("error") or {}
        raise ValueError(err.get("description", "no data"))
    meta = res["meta"]
    ind = (res.get("indicators", {}).get("quote") or [{}])[0]
    closes = [c for c in ind.get("close", []) if c is not None]
    volumes = [v for v in ind.get("volume", []) if v is not None][-10:]
    price = meta.get("regularMarketPrice") or (closes[-1] if closes else 0)
    prev = closes[-2] if len(closes) >= 2 else meta.get("chartPreviousClose") or price
    currency = meta.get("currency") or ""
    scale = 1
    if currency in ("GBp", "GBX"):          # London quotes in pence
        currency, scale = "GBP", 0.01
    price *= scale
    prev *= scale
    return {
        "name": " ".join((meta.get("shortName") or meta.get("longName") or symbol).split()),
        "price": price,
        "currency": currency,
        "prevClose": prev,
        "change": price - prev,
        "changePct": (price / prev - 1) * 100 if prev else 0,
        "spark": [c * scale for c in closes],
        "time": meta.get("regularMarketTime", 0),
        "type": meta.get("instrumentType", ""),
        # dead listings (e.g. Yahoo's MWRD.DE): stale closes, no volume
        "traded": sum(1 for v in volumes if v) >= len(volumes) / 2,
    }


def _json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f)


def kind(ident):
    ident = ident.strip().upper()
    if re.fullmatch(r"[A-Z]{2}[A-Z0-9]{9}\d", ident):
        return "ID_ISIN"
    if re.fullmatch(r"[A-Z0-9]{6}", ident) and re.search(r"\d", ident):
        return "ID_WERTPAPIER"
    return None


def resolve(ident):
    """ISIN/WKN -> Yahoo ticker (cached); tickers are returned unchanged"""
    id_type = kind(ident)
    if not id_type:
        return ident
    ident = ident.strip().upper()
    cache = _json(SYMBOLS_CACHE)
    if ident in cache:
        return cache[ident]
    req = urllib.request.Request("https://api.openfigi.com/v3/mapping", method="POST",
                                 data=json.dumps([{"idType": id_type, "idValue": ident}]).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": qsconf.UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = (json.load(r) or [{}])[0].get("data") or []
    candidates = []
    for code, suffix in EXCHANGES:
        for d in data:
            if d.get("exchCode") == code and d.get("ticker"):
                t = d["ticker"].replace("/", "-") + suffix
                if t not in candidates:
                    candidates.append(t)
    if id_type == "ID_ISIN":
        candidates.append(None)                  # last resort: Yahoo search knows some ISINs
    fallback = None
    for t in candidates:
        try:
            t = t or yahoo_search(ident)
            if not t:
                continue
            q = quote(t)
            if not q["traded"]:             # dead listing: only if nothing better
                fallback = fallback or t
                continue
            cache[ident] = t
            _save(SYMBOLS_CACHE, cache)
            return t
        except Exception:  # noqa: BLE001 - try the next listing
            continue
    if fallback:
        cache[ident] = fallback
        _save(SYMBOLS_CACHE, cache)
        return fallback
    raise ValueError(f"cannot resolve {ident} to a Yahoo ticker")


def yahoo_search(q):
    url = "https://query1.finance.yahoo.com/v1/finance/search?" + urllib.parse.urlencode(
        {"q": q, "quotesCount": 5, "newsCount": 0})
    req = urllib.request.Request(url, headers={"User-Agent": qsconf.UA})
    with urllib.request.urlopen(req, timeout=15) as r:
        quotes = json.load(r).get("quotes") or []
    return quotes[0]["symbol"] if quotes else None


def quote_any(ident):
    t = resolve(ident)
    q = quote(t)
    q["ticker"] = t
    return q


def actual_accounts(force=False):
    cfg = qsconf.section("actual")
    cache = _json(ACTUAL_CACHE)
    max_age = float(cfg.get("refreshMinutes", 30)) * 60
    if not force and cache.get("accounts") and time.time() - cache.get("time", 0) < max_age:
        return cache
    payload = dict(cfg, dataDir=os.path.join(CACHE_DIR, "actual-data"))
    try:
        r = subprocess.run(["node", os.path.join(HERE, "actual.mjs")], input=json.dumps(payload),
                           capture_output=True, text=True, timeout=120)
        res = json.loads(r.stdout or '{"error": "no output"}')
    except Exception as e:  # noqa: BLE001
        res = {"error": str(e)}
    if "error" in res:
        if cache.get("accounts"):                # keep the last good balances
            return dict(cache, error=res["error"], stale=True)
        return res
    res["time"] = time.time()
    _save(ACTUAL_CACHE, res)
    return res


# ---- Kraken -------------------------------------------------------------------

KRAKEN_API = "https://api.kraken.com"
# legacy Kraken asset codes -> common tickers
KRAKEN_ASSETS = {"XXBT": "BTC", "XBT": "BTC", "XXDG": "DOGE", "XDG": "DOGE", "XETH": "ETH",
                 "ETH2": "ETH", "XLTC": "LTC", "XXRP": "XRP", "XXLM": "XLM", "XXMR": "XMR",
                 "XZEC": "ZEC", "XETC": "ETC", "XREP": "REP", "XMLN": "MLN",
                 "ZEUR": "EUR", "ZUSD": "USD", "ZGBP": "GBP", "ZCAD": "CAD", "ZJPY": "JPY",
                 "ZAUD": "AUD", "ZCHF": "CHF"}
FIAT = {"EUR", "USD", "GBP", "CAD", "JPY", "AUD", "CHF"}
COIN_NAMES = {"BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana", "XRP": "XRP", "ADA": "Cardano",
              "DOT": "Polkadot", "DOGE": "Dogecoin", "LTC": "Litecoin", "LINK": "Chainlink",
              "ATOM": "Cosmos", "AVAX": "Avalanche", "MATIC": "Polygon", "POL": "Polygon",
              "XLM": "Stellar", "XMR": "Monero", "TRX": "Tron", "USDT": "Tether", "USDC": "USD Coin"}


def kraken_coin(asset):
    """XXBT -> BTC, DOT.S / ETH2.S / USDC.M / ETH.F -> DOT / ETH / USDC / ETH"""
    a = asset.split(".")[0].upper()
    return KRAKEN_ASSETS.get(a, a)


def kraken_private(path, cfg, **params):
    key = cfg.get("apiKey")
    secret = cfg.get("apiSecret")
    if not secret and cfg.get("apiSecretCommand"):
        secret = subprocess.run(cfg["apiSecretCommand"], shell=True, capture_output=True,
                                text=True, check=True).stdout.strip()
    if not key or not secret:
        raise ValueError("set kraken.apiKey + apiSecret (or apiSecretCommand) in private.json")
    params["nonce"] = str(int(time.time() * 1000))
    body = urllib.parse.urlencode(params)
    digest = hashlib.sha256((params["nonce"] + body).encode()).digest()
    sig = hmac.new(base64.b64decode(secret), path.encode() + digest, hashlib.sha512).digest()
    req = urllib.request.Request(KRAKEN_API + path, data=body.encode(), method="POST", headers={
        "API-Key": key, "API-Sign": base64.b64encode(sig).decode(),
        "Content-Type": "application/x-www-form-urlencoded", "User-Agent": qsconf.UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        j = json.load(r)
    if j.get("error"):
        raise ValueError("Kraken: " + ", ".join(j["error"]))
    return j["result"]


def kraken_balances(force=False):
    """{"balances": {COIN: amount}, "time"} (staked/earn variants summed), cached"""
    cfg = qsconf.section("kraken")
    cache = _json(KRAKEN_CACHE)
    max_age = float(cfg.get("refreshMinutes", 15)) * 60
    if not force and cache.get("balances") is not None and time.time() - cache.get("time", 0) < max_age:
        return cache
    try:
        raw = kraken_private("/0/private/Balance", cfg)
    except Exception as e:  # noqa: BLE001
        if cache.get("balances") is not None:   # keep the last good balances
            return dict(cache, error=str(e)[:200], stale=True)
        return {"error": str(e)[:200]}
    balances = {}
    for asset, amount in raw.items():
        coin = kraken_coin(asset)
        if coin in ("KFEE", "FEE"):
            continue
        balances[coin] = balances.get(coin, 0) + float(amount)
    res = {"balances": {c: v for c, v in balances.items() if v > 0}, "time": time.time()}
    _save(KRAKEN_CACHE, res)
    return res


def kraken_quote(coin, quote_ccys):
    """daily candles from the public OHLC API, in the first quote currency that has a pair"""
    err = None
    for ccy in quote_ccys:
        url = f"{KRAKEN_API}/0/public/OHLC?" + urllib.parse.urlencode({"pair": coin + ccy, "interval": 1440})
        req = urllib.request.Request(url, headers={"User-Agent": qsconf.UA})
        with urllib.request.urlopen(req, timeout=15) as r:
            j = json.load(r)
        if j.get("error"):
            err = ", ".join(j["error"])
            continue
        candles = next(v for k, v in j["result"].items() if k != "last")[-31:]
        closes = [float(c[4]) for c in candles]
        price = closes[-1]
        prev = closes[-2] if len(closes) >= 2 else price
        return {"name": COIN_NAMES.get(coin, coin), "price": price, "currency": ccy, "prevClose": prev,
                "change": price - prev, "changePct": (price / prev - 1) * 100 if prev else 0,
                "spark": closes, "time": int(candles[-1][0]), "type": "CRYPTOCURRENCY",
                "ticker": coin + ccy}
    raise ValueError(f"no Kraken pair for {coin}: {err}")


def kraken_portfolio(base, errors):
    """-> (holdings, cash, quotes) from the Kraken balances"""
    cfg = qsconf.section("kraken")
    bal = kraken_balances()
    if bal.get("error"):
        errors["Kraken"] = bal["error"] + (" (showing cached balances)" if bal.get("stale") else "")
    balances = bal.get("balances") or {}
    ignore = {c.upper() for c in cfg.get("ignore", [])}
    costs, names = cfg.get("cost", {}), cfg.get("names", {})
    holdings, cash, quotes = [], [], {}
    coins = [c for c in balances if c not in FIAT and c not in ignore]

    def one(c):
        try:
            return c, kraken_quote(c, list(dict.fromkeys([base, "EUR", "USD"]))), None
        except Exception as e:  # noqa: BLE001
            return c, None, str(e)[:200]

    with ThreadPoolExecutor(max_workers=8) as ex:
        for c, q, e in ex.map(one, coins):
            sym = "kraken:" + c
            if q:
                if c in names:
                    q["name"] = names[c]
                quotes[sym] = q
            else:
                errors[sym] = e
            h = {"symbol": sym, "quantity": balances[c], "name": names.get(c, COIN_NAMES.get(c, c)),
                 "source": "kraken", "url": f"https://pro.kraken.com/app/trade/{c.lower()}-{base.lower()}"}
            if c in costs:
                h["cost"] = costs[c]
            holdings.append(h)
    for c in sorted(balances):
        if c in FIAT and c not in ignore:
            cash.append({"name": f"Kraken {c}", "amount": balances[c], "currency": c, "source": "kraken"})
    return holdings, cash, quotes


def fetch_all(symbols):
    quotes, errors = {}, {}

    def one(s):
        try:
            return s, quote_any(s), None
        except Exception as e:  # noqa: BLE001
            return s, None, str(e)[:200]

    with ThreadPoolExecutor(max_workers=8) as ex:
        for s, q, e in ex.map(one, symbols):
            if q:
                quotes[s] = q
            else:
                errors[s] = e
    return quotes, errors


def main():
    cfg = qsconf.section("markets")
    base = cfg.get("base", "EUR")
    holdings = cfg.get("holdings", [])
    watch = [w if isinstance(w, str) else w["symbol"] for w in cfg.get("watchlist", [])]
    symbols = list(dict.fromkeys(watch +
                                 [h["symbol"] for h in holdings if h.get("symbol")]))
    quotes, errors = fetch_all(symbols)

    # Kraken: coins -> holdings, fiat -> cash
    auto_holdings, kraken_cash = [], []
    if qsconf.section("kraken").get("apiKey"):
        auto_holdings, kraken_cash, kq = kraken_portfolio(base, errors)
        quotes.update(kq)

    # cash: fixed amounts, or balances from Actual Budget
    cash, act = [], {}
    if any(c.get("actual") for c in cfg.get("cash", [])):
        act = actual_accounts()
        if act.get("error"):
            errors["Actual Budget"] = act["error"] + (" (showing cached balances)" if act.get("stale") else "")
    for c in cfg.get("cash", []):
        entry = {"name": c.get("name", "Cash"), "amount": c.get("amount", 0),
                 "currency": c.get("currency", base), "source": "config"}
        if c.get("actual"):
            names = c["actual"] if isinstance(c["actual"], list) else [c["actual"]]
            accs = [a for a in act.get("accounts", []) if a["name"] in names]
            missing = set(names) - {a["name"] for a in accs}
            if missing and act.get("accounts"):
                errors["Actual Budget"] = f"no account {', '.join(sorted(missing))} " \
                    f"(have: {', '.join(a['name'] for a in act['accounts'])})"
            if not accs:
                continue
            entry.update(amount=sum(a["balance"] for a in accs), source="actual")
        cash.append(entry)
    cash += kraken_cash

    # FX rates for every currency that is not the base currency
    currencies = {q["currency"] for q in quotes.values() if q["currency"]}
    currencies |= {c["currency"] for c in cash}
    currencies |= {h["currency"] for h in holdings if h.get("currency")}
    currencies.discard(base)
    fx_quotes, fx_errors = fetch_all([f"{c}{base}=X" for c in currencies])
    fx = {base: 1.0}
    for c in currencies:
        q = fx_quotes.get(f"{c}{base}=X")
        if q:
            fx[c] = q["price"]
        else:
            errors[f"{c}{base}=X"] = fx_errors.get(f"{c}{base}=X", "no data")

    # hide Kraken dust (value below kraken.minValue in the base currency)
    min_value = float(qsconf.section("kraken").get("minValue", 1))

    def worth(h):
        q = quotes.get(h["symbol"])
        return q is None or h["quantity"] * q["price"] * fx.get(q["currency"], 1) >= min_value
    auto_holdings = [h for h in auto_holdings if worth(h)]
    cash = [c for c in cash if c["source"] != "kraken" or c["amount"] * fx.get(c["currency"], 1) >= min_value]

    json.dump({"base": base, "fx": fx, "quotes": quotes, "holdings": auto_holdings, "cash": cash,
               "errors": errors},
              sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    if sys.argv[1:2] == ["resolve"] and len(sys.argv) > 2:
        for i in sys.argv[2:]:
            print(i, "->", resolve(i.upper()))
    elif sys.argv[1:2] == ["actual"]:
        print(json.dumps(actual_accounts(force=True), indent=2, ensure_ascii=False))
    elif sys.argv[1:2] == ["kraken"]:
        print(json.dumps(kraken_balances(force=True), indent=2, ensure_ascii=False))
    else:
        main()
