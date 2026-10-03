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


