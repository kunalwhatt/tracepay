"""Trace.Pay identifier rules."""
from __future__ import annotations

import re
from urllib.parse import parse_qs, urlparse

TRACEPAY_DOMAIN = "tracepay"
TRACEPAY_ID_RE = re.compile(r"^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?@tracepay$")


def normalize_tracepay_id(value: str) -> str:
    """Every Trace.Pay ID is ``name@tracepay``. A bare name gets the suffix; any other domain is rejected.

    External accounts that only appear in ingested datasets (for example ``someone@okhdfc``) are
    evidence references, not Trace.Pay IDs, so ingestion and investigator searches are unaffected.
    """
    raw = (value or "").strip().lower()
    if raw.startswith("upi://") or raw.startswith("tracepay://"):
        raw = (parse_qs(urlparse(raw).query).get("pa") or [""])[0].strip().lower()
    if "@" not in raw:
        raw = f"{raw}@{TRACEPAY_DOMAIN}"
    if not TRACEPAY_ID_RE.fullmatch(raw):
        raise ValueError("Trace.Pay IDs look like name@tracepay. Other UPI handles are not Trace.Pay accounts.")
    return raw




# ---- Any UPI QR / link (GPay, PhonePe, Paytm, BHIM, bank apps) ----
import re as _re
from urllib.parse import parse_qs, urlparse, unquote

UPI_ID_RE = _re.compile(r"^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9.]{1,40}$")


def parse_upi(raw: str) -> dict:
    """Parse a UPI QR payload (upi://pay?pa=...&pn=...&am=...) or a bare UPI ID.

    Returns {"vpa", "name", "amount", "note", "merchant_code", "txn_ref", "is_tracepay", "raw"}; vpa is None when
    nothing usable is found. Values come only from the QR; nothing is invented.
    """
    text = (raw or "").strip()
    out = {"vpa": None, "name": None, "amount": None, "note": None, "merchant_code": None, "txn_ref": None, "raw": text[:500]}
    if not text:
        return {**out, "is_tracepay": False}
    if text.lower().startswith(("upi://", "tracepay://")):
        q = parse_qs(urlparse(text).query)
        get = lambda k: unquote(q[k][0]).strip() if q.get(k) and q[k][0].strip() else None
        out.update(vpa=(get("pa") or "").lower() or None, name=get("pn"), amount=get("am"), note=get("tn"),
                   merchant_code=get("mc"), txn_ref=get("tr"))
    else:
        out["vpa"] = text.lower()
    if out["vpa"] and not UPI_ID_RE.match(out["vpa"]):
        out["vpa"] = None
    if out["amount"]:
        try:
            out["amount"] = str(round(float(out["amount"]), 2))
        except ValueError:
            out["amount"] = None
    out["is_tracepay"] = bool(out["vpa"] and out["vpa"].endswith("@tracepay"))
    return out
