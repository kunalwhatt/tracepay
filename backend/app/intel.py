"""Trace.Pay fraud intelligence: everything around TraceScore that stops a scam before, during and after payment.

Pure functions (no database), so each one is unit-tested on its own:
  analyze_text      - scam message analysis (task, fake KYC, lottery, investment, loan, digital arrest, ...)
  analyze_link      - phishing / risky link heuristics
  name_mismatch     - QR name vs the account's real name (fake-merchant signal)
  lifecycle_stage   - where an account sits in the mule lifecycle
  cooling_seconds   - risk-based cooling-off before a payment
  reporter_weight   - reputation of a community reporter (resists fake and revenge reports)
  campaigns         - groups reports into scam campaigns
"""
from __future__ import annotations

import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

# ----------------------------------------------------------------------------------------------
# Scam message analysis
# ----------------------------------------------------------------------------------------------
SCAM_PATTERNS: dict[str, dict] = {
    "task_scam": {"label": "Task / part-time job scam", "weight": 30, "terms": [
        r"like (?:youtube )?videos?", r"rate (?:hotels?|restaurants?|products?)", r"prepaid task", r"telegram (?:task|group|job)",
        r"part[- ]time job", r"work from home", r"daily (?:earn|income|salary)", r"earn (?:rs\.?|₹)?\s?\d{3,}", r"merchant task",
        r"(?:recharge|deposit|pay) to (?:unlock|withdraw|continue)", r"commission", r"review (?:job|task)"]},
    "fake_kyc": {"label": "Fake KYC / account block", "weight": 30, "terms": [
        r"\bkyc\b", r"account (?:will be |is )?(?:blocked|suspended|frozen|deactivated)", r"(?:pan|aadhaa?r) (?:update|link)",
        r"sim (?:will be )?block", r"electricity (?:will be )?(?:disconnect|cut)", r"update (?:your )?details", r"verify your account"]},
    "lottery": {"label": "Lottery / prize scam", "weight": 25, "terms": [
        r"lottery", r"you (?:have )?won", r"\bprize\b", r"lucky draw", r"\bkbc\b", r"claim (?:your )?(?:reward|prize|gift)", r"cash ?back of ₹?\d{4,}"]},
    "investment": {"label": "Investment / trading scam", "weight": 30, "terms": [
        r"guaranteed (?:returns?|profit)", r"double (?:your )?money", r"(?:stock|trading|share) tips", r"ipo allot", r"\bcrypto\b",
        r"vip (?:group|channel)", r"\d{2,3}% (?:returns?|profit)", r"risk[- ]free (?:returns?|profit)"]},
    "loan": {"label": "Instant loan scam", "weight": 20, "terms": [
        r"instant loan", r"loan (?:is )?approved", r"processing fee", r"pre[- ]approved loan", r"no cibil"]},
    "digital_arrest": {"label": "'Digital arrest' / impersonation", "weight": 35, "terms": [
        r"digital arrest", r"\bcbi\b", r"\bnarcotics\b", r"customs (?:duty|department)", r"(?:fedex|courier|parcel) (?:seized|held|contains)",
        r"arrest warrant", r"money laundering", r"police (?:case|complaint) against you", r"\btrai\b.*(?:block|disconnect)"]},
    "otp_pin": {"label": "Asks for OTP or UPI PIN", "weight": 35, "terms": [
        r"share (?:the |your )?otp", r"(?:send|tell) (?:me )?(?:the )?otp", r"upi pin", r"enter (?:your )?pin to receive", r"scan (?:this )?(?:qr )?to receive"]},
    "refund": {"label": "Fake refund / wrong transfer", "weight": 20, "terms": [
        r"sent (?:by )?mistake", r"wrong(?:ly)? transfer", r"refund (?:the|my) money", r"return (?:the|my) money"]},
}
PRESSURE_TERMS = [r"\burgent", r"immediately", r"within (?:24|48) hours", r"last chance", r"act now", r"today only", r"don'?t tell anyone"]

VPA_RE = re.compile(r"\b[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9.]{1,40}\b", re.I)
PHONE_RE = re.compile(r"(?<!\d)(?:\+?91[-\s]?)?([6-9]\d{9})(?!\d)")
URL_RE = re.compile(r"\b(?:https?://|www\.)[^\s<>\"']+|\b[a-z0-9-]+\.(?:xyz|top|click|icu|live|buzz|rest|cyou|in|com|net|org|info|online|site|link|app)/[^\s<>\"']*", re.I)
EMAIL_DOMAINS = {"gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "icloud.com", "rediffmail.com"}


def extract(text: str) -> dict:
    vpas = [v.lower() for v in VPA_RE.findall(text or "") if v.lower().split("@", 1)[1] not in EMAIL_DOMAINS]
    phones = PHONE_RE.findall(text or "")
    urls = URL_RE.findall(text or "")
    dedupe = lambda xs: list(dict.fromkeys(xs))
    return {"upi_ids": dedupe(vpas)[:5], "phones": dedupe(phones)[:5], "links": dedupe(urls)[:5]}


def analyze_text(text: str) -> dict:
    """Score a forwarded SMS / WhatsApp / Telegram message for scam language."""
    low = (text or "").lower()
    found = []
    for code, p in SCAM_PATTERNS.items():
        hits = [m.group(0) for t in p["terms"] for m in [re.search(t, low)] if m]
        if hits:
            found.append({"code": code, "label": p["label"], "points": min(p["weight"] + 5 * (len(hits) - 1), p["weight"] + 15), "matched": hits[:4]})
    pressure = [m.group(0) for t in PRESSURE_TERMS for m in [re.search(t, low)] if m]
    if pressure:
        found.append({"code": "PRESSURE", "label": "Pressure to act fast", "points": 10 + 5 * min(len(pressure) - 1, 2), "matched": pressure[:3]})
    pay = re.search(r"(?:pay|send|transfer) (?:rs\.?|₹)?\s?\d+", low)
    if pay and found:
        found.append({"code": "PAYMENT_REQUEST", "label": "Asks you to pay", "points": 10, "matched": [pay.group(0)]})
    parts = extract(text)
    links = [analyze_link(u) for u in parts["links"]]
    worst = max(links, key=lambda l: l["score"], default=None)
    if worst and worst["score"] >= 25:
        found.append({"code": "RISKY_LINK", "label": "Contains a risky link", "points": min(30, worst["score"] // 2), "matched": [worst["host"]]})
    score = min(100, sum(f["points"] for f in found))
    band = "high_review" if score >= 75 else "review" if score >= 50 else "watch" if score >= 25 else "low"
    return {"score": score, "band": band, "signals": sorted(found, key=lambda f: -f["points"]), **parts, "link_checks": links}


# ----------------------------------------------------------------------------------------------
# Links
# ----------------------------------------------------------------------------------------------
SHORTENERS = {"bit.ly", "tinyurl.com", "cutt.ly", "rb.gy", "t.ly", "is.gd", "shorturl.at", "tiny.cc", "goo.gl", "ow.ly", "s.id", "rebrand.ly"}
RISKY_TLDS = {"xyz", "top", "click", "icu", "live", "buzz", "rest", "cyou", "monster", "quest", "sbs", "cfd", "gq", "tk", "ml", "ga", "cf"}
BRANDS = {"sbi": "onlinesbi.sbi", "hdfc": "hdfcbank.com", "icici": "icicibank.com", "axis": "axisbank.com", "kotak": "kotak.com",
          "paytm": "paytm.com", "phonepe": "phonepe.com", "gpay": "pay.google.com", "npci": "npci.org.in", "rbi": "rbi.org.in",
          "incometax": "incometax.gov.in", "uidai": "uidai.gov.in", "aadhaar": "uidai.gov.in", "epfo": "epfindia.gov.in", "bescom": "bescom.co.in"}


def analyze_link(url: str) -> dict:
    raw = (url or "").strip()
    u = urlparse(raw if "://" in raw else "http://" + raw)
    host = (u.hostname or "").lower()
    signals = []
    add = lambda code, label, pts: signals.append({"code": code, "label": label, "points": pts})
    if not host:
        return {"url": raw, "host": "", "score": 0, "band": "low", "signals": []}
    if host in SHORTENERS: add("SHORTENER", "Shortened link hides the real address", 20)
    if re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", host): add("IP_HOST", "Link points to a bare IP address", 30)
    if host.rsplit(".", 1)[-1] in RISKY_TLDS: add("RISKY_TLD", f"Unusual domain ending .{host.rsplit('.', 1)[-1]}", 20)
    if "xn--" in host: add("PUNYCODE", "Look-alike characters in the address", 30)
    if host.count("-") >= 2: add("HYPHENS", "Many hyphens, common in fake sites", 10)
    if u.scheme == "http": add("NO_HTTPS", "Not a secure (https) link", 10)
    if (u.path or "").lower().endswith(".apk"): add("APK", "Downloads an Android app from outside the Play Store", 35)
    for brand, official in BRANDS.items():
        if brand in host.replace("-", "").replace(".", "") and not (host == official or host.endswith("." + official)):
            add("LOOKALIKE", f"Uses the name '{brand.upper()}' but isn't the official {official}", 35); break
    score = min(100, sum(s["points"] for s in signals))
    band = "high_review" if score >= 75 else "review" if score >= 50 else "watch" if score >= 25 else "low"
    return {"url": raw, "host": host, "score": score, "band": band, "signals": signals}


# ----------------------------------------------------------------------------------------------
# Account-level signals added to TraceScore
# ----------------------------------------------------------------------------------------------
def _tokens(name: str) -> set[str]:
    return {t for t in re.split(r"[^a-z0-9]+", (name or "").lower()) if len(t) >= 3 and t not in {"the", "and", "pvt", "ltd", "shop", "store"}}


def name_mismatch(qr_name: str | None, real_name: str | None) -> dict | None:
    """The QR claims one name but the account belongs to someone else: a classic fake-merchant signal."""
    a, b = _tokens(qr_name or ""), _tokens(real_name or "")
    if not a or not b or a & b:
        return None
    return {"code": "NAME_MISMATCH", "label": "QR name doesn't match the account", "family": "trust", "points": 15,
            "detail": f'The QR says "{qr_name}", but the account belongs to "{real_name}".'}


def lifecycle_stage(records: int, first_seen: datetime | None, last_seen: datetime | None, factor_codes: set[str], now: datetime | None = None) -> dict:
    """Where the account sits in the mule lifecycle: no history → new → established, or recruited → active mule."""
    now = now or datetime.now(timezone.utc)
    age_days = (now - first_seen).days if first_seen else 0
    if {"MULE_LIFECYCLE", "PASS_THROUGH", "FAN_IN_OUT", "RAPID_ONWARD", "HIGH_FORWARDING"} & factor_codes and records >= 5:
        return {"stage": "active_mule", "label": "Active mule pattern", "detail": "Money arrives from many people and leaves again quickly."}
    if records >= 8 and age_days <= 7:
        return {"stage": "recruited", "label": "New and suddenly busy", "detail": "A new account with unusually heavy activity, typical of freshly recruited mules."}
    if records == 0:
        return {"stage": "unknown", "label": "No history", "detail": "trace.pay hasn't seen this account move money yet."}
    if age_days < 30:
        return {"stage": "new", "label": "New account", "detail": f"First seen {age_days} day{'s' if age_days != 1 else ''} ago."}
    return {"stage": "established", "label": "Established", "detail": f"Active for {age_days} days with {records} payments seen."}


def cooling_seconds(score: int | None, band: str, first_payment: bool, amount: float | None) -> int:
    """Risk-based pause before paying: higher risk, first payment and larger amounts mean a longer wait."""
    s = score or 0
    amt = amount or 0
    if s >= 75: return 600
    if s >= 50: return 300 if amt >= 1000 or first_payment else 120
    if first_payment and amt >= 5000: return 60 if s < 25 else 180
    return 0


def reporter_weight(confirmed: int, rejected: int, total: int) -> float:
    """0.2–1.0. New reporters start at 0.6; confirmed reports raise it, rejected ones lower it."""
    if total <= 0: return 0.6
    return round(max(0.2, min(1.0, 0.6 + 0.4 * (confirmed / total) - 0.6 * (rejected / total))), 2)


# ----------------------------------------------------------------------------------------------
# Campaigns: many reports, one operation
# ----------------------------------------------------------------------------------------------
def campaigns(reports: list[dict], min_size: int = 2) -> list[dict]:
    """Group reports that share a target account, or the same category with very similar wording."""
    n = len(reports); parent = list(range(n))
    def find(i):
        while parent[i] != i: parent[i] = parent[parent[i]]; i = parent[i]
        return i
    def union(i, j): parent[find(i)] = find(j)
    toks = [_tokens(r.get("description", "")) for r in reports]
    by_target = defaultdict(list)
    for i, r in enumerate(reports): by_target[r["target_ref"]].append(i)
    for idx in by_target.values():
        for j in idx[1:]: union(idx[0], j)
    for i in range(n):
        for j in range(i + 1, n):
            if reports[i]["category"] == reports[j]["category"] and toks[i] and toks[j]:
                if len(toks[i] & toks[j]) / len(toks[i] | toks[j]) >= 0.5: union(i, j)
    groups = defaultdict(list)
    for i in range(n): groups[find(i)].append(reports[i])
    out = []
    for members in groups.values():
        if len(members) < min_size: continue
        cats = defaultdict(int)
        for m in members: cats[m["category"]] += 1
        amounts = [float(m["amount"]) for m in members if m.get("amount")]
        out.append({"size": len(members), "category": max(cats, key=cats.get), "accounts": sorted({m["target_ref"] for m in members}),
                    "total_lost": round(sum(amounts), 2), "first": min(m["created_at"] for m in members), "last": max(m["created_at"] for m in members),
                    "report_ids": [m["id"] for m in members]})
    return sorted(out, key=lambda c: (-c["size"], -c["total_lost"]))
