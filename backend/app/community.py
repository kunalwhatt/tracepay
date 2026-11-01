"""Truecaller-style safety layer: one explainable verdict for any UPI ID.

The verdict combines TraceScore (behaviour in the evidence graph) with community signals (moderated scam
reports, complaints, investigator decisions) and trust signals (verified merchants). Every factor is listed
with its points, so the pop-up shown before a payment can explain exactly why.
"""
from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone

VPA_RE = re.compile(r"[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9.]{1,40}", re.I)
CATEGORIES = {"scam_payment": "Scam payment", "task_scam": "Task scam", "investment_scam": "Investment scam",
              "fake_merchant": "Fake merchant / shop", "loan_app": "Loan app harassment", "impersonation": "Impersonation (bank, KYC, police)",
              "lottery_prize": "Lottery / prize scam", "other": "Other"}
VERDICTS = {
    "high_review": ("High risk", "Strong scam pattern. Do not pay unless you know this person well."),
    "review": ("Risky", "Several warning signs. Check carefully before paying."),
    "watch": ("Be careful", "Some warning signs. Make sure you know who you are paying."),
    "low": ("No warning signs", "Nothing suspicious found in Trace.Pay's records."),
    "insufficient_information": ("Not enough history", "This account is new to Trace.Pay. Pay only people you know."),
}
BANDS = [(75, "high_review"), (50, "review"), (25, "watch"), (0, "low")]


def mask(text: str) -> str:
    """Hide other people's IDs inside explanations shown to members (ab***@okaxis)."""
    return VPA_RE.sub(lambda m: m.group(0).split("@")[0][:2] + "***@" + m.group(0).split("@")[1], text or "")


def band_for(score: int) -> str:
    return next(key for floor, key in BANDS if score >= floor)


def community_factors(reports: list, complaints: int, label: str | None, merchant: dict | None, now: datetime | None = None) -> list[dict]:
    now = now or datetime.now(timezone.utc)
    factors = []
    active = [r for r in reports if r.status != "rejected"]
    verified = [r for r in active if r.status == "verified"]
    recent = [r for r in active if (now - (r.created_at if r.created_at.tzinfo else r.created_at.replace(tzinfo=timezone.utc))) <= timedelta(days=90)]
    if verified:
        factors.append({"code": "VERIFIED_REPORTS", "label": "Scam reports confirmed by investigators", "family": "community",
                        "points": min(40, 20 + 10 * (len(verified) - 1)), "detail": f"{len(verified)} confirmed report(s)"})
    if recent:
        cats = sorted({CATEGORIES.get(r.category, "Other") for r in recent})
        factors.append({"code": "COMMUNITY_REPORTS", "label": "Reported by Trace.Pay users", "family": "community",
                        "points": min(30, 8 * len(recent)), "detail": f"{len(recent)} report(s) in 90 days: {', '.join(cats)}"})
    if complaints:
        factors.append({"code": "COMPLAINTS", "label": "Named in victim complaints", "family": "community",
                        "points": min(30, 15 * complaints), "detail": f"{complaints} complaint(s)"})
    if label == "confirmed_fraud":
        factors.append({"code": "INVESTIGATOR_FLAG", "label": "Flagged by investigators", "family": "community", "points": 40,
                        "detail": "Confirmed as fraudulent after review"})
    if label == "not_suspicious":
        factors.append({"code": "INVESTIGATOR_CLEARED", "label": "Cleared by investigators", "family": "trust", "points": -25,
                        "detail": "Reviewed and found not suspicious"})
    if merchant and merchant.get("verified"):
        factors.append({"code": "VERIFIED_MERCHANT", "label": "Verified merchant", "family": "trust", "points": -20,
                        "detail": f"{merchant.get('display_name')} · {merchant.get('category')}"})
    return factors


def combine(trace: dict, extra: list[dict]) -> dict:
    """Merge TraceScore contributions with community and trust factors into one explained score."""
    factors = [{"code": c["code"], "label": c["label"], "family": c.get("family", "deep"), "points": c["points"], "detail": c.get("detail") or ""}
               for c in trace.get("contributions", [])] + extra
    if trace.get("score") is None and not extra:
        # No history yet: still return a number so the meter always has something to show.
        return {"score": 20, "band": "insufficient_information",
                "factors": [{"code": "NEW_ACCOUNT", "label": "No payment history yet", "family": "core", "points": 20,
                             "detail": "trace.pay has not seen this account before. Pay only people you know."}]}
    score = max(0, min(100, sum(f["points"] for f in factors)))
    factors.sort(key=lambda f: -abs(f["points"]))
    return {"score": score, "band": band_for(score), "factors": factors}


def verdict(band: str) -> dict:
    title, advice = VERDICTS[band]
    return {"title": title, "advice": advice}
