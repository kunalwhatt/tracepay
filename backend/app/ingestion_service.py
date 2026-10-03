from __future__ import annotations

import csv
import hashlib
import io
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any
from zoneinfo import ZoneInfo
import os
from uuid import uuid4

import pandas as pd
from dateutil import parser as date_parser


CANONICAL = {
    "transaction_id": ["transaction_id", "transactionid", "txn_id", "txn", "txnid", "txn_ref", "transaction_ref", "reference", "ref", "id"],
    "event_id": ["event_id", "eventid", "event", "event_ref"],
    "sender_id": ["sender_id", "sender", "payer", "from", "from_id", "source", "sender_account", "sender_upi", "source_account", "debit_account", "debited_account", "remitter"],
    "receiver_id": ["receiver_id", "receiver", "payee", "to", "to_id", "destination", "destination_account", "credit_account", "credited_account", "beneficiary"],
    "amount": ["amount", "txn_amount", "transaction_amount", "value", "amount_inr", "amount_rs", "debit_amount", "credit_amount"],
    "currency": ["currency", "ccy", "curr"],
    "timestamp": ["timestamp", "datetime", "date_time", "transaction_time", "txn_time", "occurred_at", "occurred", "txn_date", "transaction_date", "time", "date"],
    "source_record_ref": ["source_record_ref", "source_record", "record_ref", "record_id", "row_id", "row_number", "row_no"],
}


def norm_header(value: Any) -> str:
    s = str(value or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s


def clean_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def parse_amount(value: Any) -> Decimal:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        raise ValueError("amount is empty")
    if isinstance(value, (int, float, Decimal)):
        result = Decimal(str(value))
    else:
        raw = str(value).strip().replace("₹", "").replace("INR", "").replace("Rs.", "").replace("Rs", "")
        raw = raw.replace(",", "").replace(" ", "")
        if raw.startswith("(") and raw.endswith(")"):
            raw = "-" + raw[1:-1]
        result = Decimal(raw)
    if result <= 0:
        raise ValueError("amount must be positive")
    return result.quantize(Decimal("0.01"))


ISO_DATE = re.compile(r"^\s*\d{4}-\d{1,2}-\d{1,2}")
NUMERIC_DATE = re.compile(r"^\s*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})")


def dayfirst_default() -> bool:
    # Indian sources write dates as DD/MM/YYYY. Override with INGESTION_DAYFIRST=false for MM/DD sources.
    return os.getenv("INGESTION_DAYFIRST", "true").strip().lower() in {"1", "true", "yes", "on"}


def parse_timestamp_ex(value: Any, dayfirst: bool | None = None) -> tuple[datetime, bool]:
    """Parse a timestamp and report whether its day/month order was ambiguous.

    ISO dates (YYYY-MM-DD) are always read year-month-day. Numeric dates such as 03/10/2026 are
    read day-first by default; when both parts could be a month the row is flagged as ambiguous so
    the interpretation is visible in provenance instead of silently assumed.
    """
    if value is None or (isinstance(value, float) and pd.isna(value)):
        raise ValueError("timestamp is empty")
    ambiguous = False
    if isinstance(value, pd.Timestamp):
        dt = value.to_pydatetime()
    elif isinstance(value, datetime):
        dt = value
    else:
        raw = clean_text(value)
        if not raw:
            raise ValueError("timestamp is empty")
        use_dayfirst = dayfirst_default() if dayfirst is None else dayfirst
        try:
            if ISO_DATE.match(raw):
                dt = date_parser.parse(raw, yearfirst=True, dayfirst=False, fuzzy=False)
            else:
                match = NUMERIC_DATE.match(raw)
                if match:
                    first, second = int(match.group(1)), int(match.group(2))
                    ambiguous = first <= 12 and second <= 12 and first != second
                dt = date_parser.parse(raw, dayfirst=use_dayfirst, fuzzy=False)
        except (ValueError, OverflowError) as exc:
            raise ValueError(f"invalid timestamp: {raw}") from exc
    if dt.tzinfo is None:
        # India-focused pilot default; override with INGESTION_DEFAULT_TIMEZONE when a source uses another local zone.
        zone = ZoneInfo(os.getenv("INGESTION_DEFAULT_TIMEZONE", "Asia/Kolkata"))
        dt = dt.replace(tzinfo=zone)
    return dt.astimezone(timezone.utc), ambiguous


def parse_timestamp(value: Any, dayfirst: bool | None = None) -> datetime:
    return parse_timestamp_ex(value, dayfirst)[0]


def detect_delimiter(raw: bytes) -> str:
    sample = raw[:100_000].decode("utf-8-sig", errors="replace")
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;|\t").delimiter
    except csv.Error:
        return ","


def read_upload(filename: str, raw: bytes) -> dict[str, pd.DataFrame]:
    lower = filename.lower()
    if lower.endswith(".xlsx") or lower.endswith(".xlsm"):
        sheets = pd.read_excel(io.BytesIO(raw), sheet_name=None, engine="openpyxl")
        return {str(name): frame for name, frame in sheets.items() if not frame.empty}
    if lower.endswith(".xls"):
        sheets = pd.read_excel(io.BytesIO(raw), sheet_name=None, engine="xlrd")
        return {str(name): frame for name, frame in sheets.items() if not frame.empty}
    if lower.endswith(".csv") or lower.endswith(".txt"):
        delimiter = detect_delimiter(raw)
        frame = pd.read_csv(io.BytesIO(raw), sep=delimiter, dtype=object, keep_default_na=False, encoding="utf-8-sig")
        return {"csv": frame} if not frame.empty else {}
    raise ValueError("Unsupported file type. Use CSV, XLSX, XLSM or XLS.")


def deterministic_mapping(columns: list[str]) -> dict[str, str]:
    normalized = {norm_header(c): c for c in columns}
    mapping: dict[str, str] = {}
    for canonical, aliases in CANONICAL.items():
        for alias in aliases:
            if alias in normalized:
                mapping[canonical] = normalized[alias]
                break
    return mapping


@dataclass
class NormalizedRow:
    transaction_id: str
    event_id: str
    sender_id: str
    receiver_id: str
    amount: Decimal
    currency: str
    timestamp: datetime
    source_record_ref: str
    quality: str
    repairs: list[str]
    sheet: str = ""
    row_no: int = 0
    fingerprint: str = ""


def content_fingerprint(sender: str, receiver: str, amount: Decimal, currency: str, timestamp: datetime, occurrence: int) -> str:
    """Deterministic identity for a row that has no IDs of its own.

    Re-uploading the same file reproduces the same fingerprints, so duplicates are detected.
    ``occurrence`` distinguishes genuinely repeated identical transfers inside one upload.
    """
    core = f"{sender}|{receiver}|{amount}|{currency}|{timestamp.isoformat()}#{occurrence}"
    return hashlib.sha256(core.encode()).hexdigest()[:32].upper()


def normalize_row(row: dict[str, Any], mapping: dict[str, str], row_no: int, sheet: str,
                  occurrences: dict[str, int] | None = None) -> NormalizedRow:
    def value(canonical: str) -> Any:
        column = mapping.get(canonical)
        return row.get(column) if column else None

    repairs: list[str] = []
    sender_id = clean_text(value("sender_id"))
    receiver_id = clean_text(value("receiver_id"))
    if not sender_id:
        raise ValueError("sender_id is missing")
    if not receiver_id:
        raise ValueError("receiver_id is missing")
    if sender_id == receiver_id:
        raise ValueError("sender_id and receiver_id are identical")

    amount = parse_amount(value("amount"))
    timestamp, ambiguous = parse_timestamp_ex(value("timestamp"))
    if ambiguous:
        repairs.append("ambiguous day/month read as " + ("DD/MM" if dayfirst_default() else "MM/DD"))
    currency = clean_text(value("currency")).upper() or "INR"
    if len(currency) != 3:
        currency = "INR"
        repairs.append("normalized currency to INR")

    core_key = f"{sender_id}|{receiver_id}|{amount}|{currency}|{timestamp.isoformat()}"
    occurrence = 0
    if occurrences is not None:
        occurrence = occurrences.get(core_key, 0)
        occurrences[core_key] = occurrence + 1
    fingerprint = content_fingerprint(sender_id, receiver_id, amount, currency, timestamp, occurrence)

    transaction_id = clean_text(value("transaction_id"))
    supplied_transaction_id = bool(transaction_id)
    if not transaction_id:
        transaction_id = "FP-" + fingerprint[:20]
        repairs.append("derived transaction_id from content fingerprint")
    event_id = clean_text(value("event_id"))
    if not event_id:
        # A supplied transaction ID is part of the identity: two distinct references with identical
        # content are two transactions, not a duplicate.
        seed = f"{transaction_id}|{fingerprint}" if supplied_transaction_id else fingerprint
        event_id = "EVT-" + hashlib.sha256(seed.encode()).hexdigest()[:32].upper()
        repairs.append("derived event_id from content fingerprint")
    source_ref = clean_text(value("source_record_ref"))
    if not source_ref:
        source_ref = "FP:" + fingerprint
        repairs.append("derived source_record_ref from content fingerprint")

    # Generated identifiers are bookkeeping, not value repairs: a row is still "observed" when
    # the financial values themselves came straight from the source.
    value_repairs = [r for r in repairs if not r.startswith("derived ")]
    return NormalizedRow(
        transaction_id=transaction_id[:128], event_id=event_id[:128], sender_id=sender_id[:255],
        receiver_id=receiver_id[:255], amount=amount, currency=currency[:3], timestamp=timestamp,
        source_record_ref=source_ref[:255], quality="normalized" if value_repairs else "observed", repairs=repairs,
        sheet=sheet, row_no=row_no, fingerprint=fingerprint,
    )


def sample_for_ai(frame: pd.DataFrame, rows: int = 8) -> list[dict[str, Any]]:
    sample = frame.head(rows).copy().fillna("")
    return json.loads(sample.to_json(orient="records", date_format="iso"))
