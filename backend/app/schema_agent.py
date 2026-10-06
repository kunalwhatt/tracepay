"""Schema agent: turn arbitrary real transaction files into Trace.Pay records.

Two dataset shapes are understood:

* **transfers**: one row per transfer with a sender and a receiver (exports, case files, ledgers).
* **statement**: one account's bank / UPI statement. Rows have a date, a narration and either
  separate withdrawal / deposit columns, an amount plus a Dr/Cr marker, or a signed amount.
  The statement owner is one side of every row; the other side comes from a counterparty column
  or is extracted from the narration (UPI ID, name, ATM, bank charges ...).

The pipeline is: find the real header row (statements often start with a preamble), propose a
plan with deterministic rules, ask Gemini to fill gaps (column names only, never values), validate
the plan, then normalise each row. Every derived value is recorded as a repair note on the row.
"""
from __future__ import annotations

import csv
import io
import re
import time
from datetime import date as date_type, datetime, time as time_type
from decimal import Decimal, InvalidOperation
from typing import Any

import pandas as pd

from . import gemini_service
from .ingestion_service import (NormalizedRow, clean_text, content_fingerprint, dayfirst_default, detect_delimiter,
                                norm_header, parse_timestamp_ex)

# --------------------------------------------------------------------------------------
# Field vocabulary
# --------------------------------------------------------------------------------------

FIELD_HELP = {
    "transaction_id": "Unique reference / UTR / RRN for the transaction",
    "sender_id": "Account, UPI ID or customer that sent money (transfer files)",
    "receiver_id": "Account, UPI ID or customer that received money (transfer files)",
    "sender_name": "Sender's name when there is no sender ID",
    "receiver_name": "Receiver's name when there is no receiver ID",
    "amount": "Single amount column (may be signed or carry Dr/Cr)",
    "debit_amount": "Money out: withdrawal / debit column (statements)",
    "credit_amount": "Money in: deposit / credit column (statements)",
    "direction": "Column saying Dr/Cr, Debit/Credit, In/Out",
    "timestamp": "Full date-time column",
    "date": "Date-only column",
    "time": "Time-only column",
    "description": "Narration / remarks / particulars text",
    "counterparty": "The other party in a statement row",
    "account_id": "Column holding the statement owner's account or UPI ID",
    "currency": "Currency code",
    "source_record_ref": "Row / record identifier in the source system",
    "event_id": "Event identifier from a streaming source",
}
FIELDS = list(FIELD_HELP)

ALIASES: dict[str, list[str]] = {
    "transaction_id": ["transaction_id", "transactionid", "txn_id", "txnid", "txn_ref", "transaction_ref", "txn_ref_no",
                       "reference", "reference_no", "reference_number", "ref_no", "refno", "ref", "chq_ref_no", "chq_ref",
                       "cheque_no", "chq_no", "utr", "utr_no", "utr_number", "rrn", "upi_ref", "upi_ref_no", "transaction_reference",
                       "txn_reference", "id", "txn"],
    "event_id": ["event_id", "eventid", "event_ref"],
    "sender_id": ["sender_id", "sender", "payer", "payer_vpa", "payer_upi", "from", "from_id", "from_account", "source_account",
                  "sender_account", "sender_upi", "sender_vpa", "debit_account", "debited_account", "remitter", "remitter_account",
                  "originator", "source"],
    "receiver_id": ["receiver_id", "receiver", "payee", "payee_vpa", "payee_upi", "to", "to_id", "to_account", "destination",
                    "destination_account", "receiver_account", "receiver_upi", "receiver_vpa", "credit_account", "credited_account",
                    "beneficiary", "beneficiary_account", "beneficiary_upi"],
    "sender_name": ["sender_name", "payer_name", "from_name", "remitter_name"],
    "receiver_name": ["receiver_name", "payee_name", "to_name", "beneficiary_name"],
    "debit_amount": ["withdrawal", "withdrawals", "withdrawal_amt", "withdrawal_amount", "withdrawal_amt_inr", "debit", "debits",
                     "debit_amt", "debit_amount", "dr_amount", "dr_amt", "money_out", "paid_out", "amount_debited", "withdrawal_dr"],
    "credit_amount": ["deposit", "deposits", "deposit_amt", "deposit_amount", "deposit_amt_inr", "credit", "credits", "credit_amt",
                      "credit_amount", "cr_amount", "cr_amt", "money_in", "paid_in", "amount_credited", "deposit_cr"],
    "amount": ["amount", "txn_amount", "transaction_amount", "amt", "value", "amount_inr", "amount_rs", "inr", "transaction_value"],
    "direction": ["dr_cr", "drcr", "cr_dr", "crdr", "debit_credit", "credit_debit", "dc", "d_c", "type", "txn_type",
                  "transaction_type", "nature", "direction", "flow"],
    "timestamp": ["timestamp", "datetime", "date_time", "transaction_datetime", "txn_datetime", "transaction_timestamp",
                  "occurred_at", "created_at", "txn_date_time", "transaction_date_time", "event_time"],
    "date": ["date", "txn_date", "transaction_date", "tran_date", "value_date", "value_dt", "posting_date", "post_date",
             "book_date", "booking_date", "trans_date"],
    "time": ["time", "txn_time", "transaction_time", "tran_time"],
    "description": ["narration", "description", "particulars", "remarks", "details", "transaction_details", "transaction_remarks",
                    "memo", "narrative", "txn_description", "transaction_description", "transaction_particulars", "comments"],
    "counterparty": ["counterparty", "counter_party", "counterparty_name", "party", "party_name", "merchant", "merchant_name",
                     "name", "other_party"],
    "account_id": ["account", "account_no", "account_number", "acct_no", "acc_no", "account_id", "upi_id", "vpa", "own_account"],
    "currency": ["currency", "ccy", "curr", "currency_code"],
    "source_record_ref": ["source_record_ref", "source_record", "record_ref", "record_id", "row_id", "row_number", "row_no", "s_no",
                          "sno", "sr_no", "serial_no"],
}
IGNORED_HEADERS = {"balance", "closing_balance", "running_balance", "available_balance", "bal", "closing_bal"}
KNOWN_TOKENS = {alias for aliases in ALIASES.values() for alias in aliases} | IGNORED_HEADERS

OUT_WORDS = {"DR", "D", "DEBIT", "DEBITED", "WITHDRAWAL", "W", "OUT", "PAID", "SENT", "PAYMENT", "OUTWARD"}
IN_WORDS = {"CR", "C", "CREDIT", "CREDITED", "DEPOSIT", "IN", "RECEIVED", "INWARD", "REFUND"}

# Hyphens are excluded: statement narrations use "-" as a separator (e.g. "UPI-NAME-ravi@okaxis-...").
UPI_RE = re.compile(r"(?<![a-z0-9._])([a-z0-9][a-z0-9._]{1,63}@[a-z][a-z0-9]{1,30})\b", re.I)
ACCOUNT_RE = re.compile(r"(?:a/?c|account)\s*(?:no\.?|number|#)?\s*[:\-]?\s*([X*\d][X*\d\s-]{5,24}\d)", re.I)
STOP = {"UPI", "DR", "CR", "IMPS", "NEFT", "RTGS", "P2A", "P2M", "P2P", "PAYMENT", "PAYMENTS", "TRANSFER", "TRF", "TO", "FROM", "BY",
        "REF", "TXN", "MB", "IB", "INB", "ACH", "NACH", "ECS", "POS", "CHQ", "CLG", "SENT", "RECEIVED", "USING", "VIA", "FOR",
        "BANK", "LTD", "PVT", "LIMITED", "SBI", "HDFC", "ICICI", "AXIS", "KOTAK", "YES", "PNB", "BOB", "CANARA", "UNION",
        "IDFC", "INDUSIND", "PAYTM", "PHONEPE", "GPAY", "YBL", "OKAXIS", "OKHDFCBANK", "OKICICI", "OKSBI", "IBL", "AXL",
        "APL", "UPIINTENT", "COLLECT", "REQUEST", "PAY", "MOBILE", "NET", "BANKING", "ONLINE", "SELF", "NA", "NIL"}

# --------------------------------------------------------------------------------------
# Loading: find the real header row, keep the preamble text
# --------------------------------------------------------------------------------------

def _decode(raw: bytes) -> str:
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _header_score(cells: list[Any]) -> int:
    names = [norm_header(c) for c in cells if clean_text(c)]
    return sum(1 for n in names if n in KNOWN_TOKENS)


def _frame_from_grid(grid: list[list[Any]], max_scan: int = 40) -> tuple[pd.DataFrame, int, str]:
    rows = [list(r) for r in grid]
    if not rows:
        return pd.DataFrame(), 0, ""
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    best, best_score = 0, -1
    for i, r in enumerate(rows[:max_scan]):
        score = _header_score(r)
        if score > best_score:
            best, best_score = i, score
    if best_score < 2:
        best = 0  # no recognisable header: assume the first row and let the plan / AI decide
    header = []
    seen: dict[str, int] = {}
    for j, cell in enumerate(rows[best]):
        name = clean_text(cell) or f"column_{j + 1}"
        if name in seen:
            seen[name] += 1
            name = f"{name}_{seen[name]}"
        else:
            seen[name] = 1
        header.append(name)
    body = [r for r in rows[best + 1:] if any(clean_text(c) for c in r)]
    frame = pd.DataFrame(body, columns=header, dtype=object)
    # Drop columns that are entirely empty (common in exported statements).
    frame = frame[[c for c in frame.columns if frame[c].map(clean_text).astype(bool).any()]]
    preamble = " | ".join(" ".join(clean_text(c) for c in r if clean_text(c)) for r in rows[:best] if any(clean_text(c) for c in r))
    return frame, best, preamble[:2000]


def load_sheets(filename: str, raw: bytes) -> dict[str, dict[str, Any]]:
    """Return {sheet: {"frame", "header_row", "preamble"}} for every non-empty sheet."""
    lower = filename.lower()
    grids: dict[str, list[list[Any]]] = {}
    if lower.endswith((".xlsx", ".xlsm", ".xls")):
        engine = "xlrd" if lower.endswith(".xls") else "openpyxl"
        for name, df in pd.read_excel(io.BytesIO(raw), sheet_name=None, header=None, dtype=object, engine=engine).items():
            grids[str(name)] = df.where(pd.notna(df), "").values.tolist()
    elif lower.endswith((".csv", ".txt", ".tsv")):
        text = _decode(raw)
        delimiter = "\t" if lower.endswith(".tsv") else detect_delimiter(raw)
        grids["csv"] = list(csv.reader(io.StringIO(text), delimiter=delimiter))
    else:
        raise ValueError("Unsupported file type. Use CSV, TXT, TSV, XLSX, XLSM or XLS.")
    out = {}
    for name, grid in grids.items():
        frame, header_row, preamble = _frame_from_grid(grid)
        if not frame.empty:
            out[name] = {"frame": frame, "header_row": header_row, "preamble": preamble}
    return out


def profile_columns(frame: pd.DataFrame, limit: int = 4) -> list[dict[str, Any]]:
    profile = []
    for col in frame.columns:
        values = [clean_text(v) for v in frame[col].tolist()]
        filled = [v for v in values if v]
        profile.append({"column": col, "filled": len(filled), "samples": filled[:limit]})
    return profile


# --------------------------------------------------------------------------------------
# Planning
# --------------------------------------------------------------------------------------

PRIORITY = ["transaction_id", "debit_amount", "credit_amount", "amount", "direction", "sender_id", "receiver_id", "timestamp",
            "date", "time", "description", "counterparty", "account_id", "sender_name", "receiver_name", "currency",
            "source_record_ref", "event_id"]


def rule_mapping(columns: list[str]) -> dict[str, str]:
    by_norm = {}
    for c in columns:
        by_norm.setdefault(norm_header(c), c)
    mapping: dict[str, str] = {}
    used: set[str] = set()
    for field in PRIORITY:
        for alias in ALIASES[field]:
            col = by_norm.get(alias)
            if col and col not in used:
                mapping[field] = col
                used.add(col)
                break
    return mapping


def _has_time(m: dict[str, str]) -> bool:
    return any(k in m for k in ("timestamp", "date", "time"))


def missing_for(mode: str, m: dict[str, str]) -> list[str]:
    if mode == "transfers":
        checks = (("sender", "sender_id" in m or "sender_name" in m), ("receiver", "receiver_id" in m or "receiver_name" in m),
                  ("amount", "amount" in m), ("timestamp or date", _has_time(m)))
    else:
        checks = (("amount, or debit / credit columns", any(k in m for k in ("amount", "debit_amount", "credit_amount"))),
                  ("timestamp or date", _has_time(m)),
                  ("description or counterparty", "description" in m or "counterparty" in m))
    return [name for name, ok in checks if not ok]


def decide_mode(m: dict[str, str]) -> tuple[str | None, list[str]]:
    """Choose the dataset shape from the mapped fields and list what is still missing for it."""
    has_sender = "sender_id" in m or "sender_name" in m
    has_receiver = "receiver_id" in m or "receiver_name" in m
    statement_money = "debit_amount" in m or "credit_amount" in m or ("amount" in m and "direction" in m)
    if has_sender and has_receiver:
        return "transfers", missing_for("transfers", m)
    if statement_money or ("amount" in m and ("description" in m or "counterparty" in m)):
        return "statement", missing_for("statement", m)
    missing = []
    if not any(k in m for k in ("amount", "debit_amount", "credit_amount")):
        missing.append("amount (or debit / credit columns)")
    if not _has_time(m):
        missing.append("timestamp or date")
    missing.append("sender + receiver, or a statement narration")
    return None, missing


def guess_statement_account(frame: pd.DataFrame, m: dict[str, str], preamble: str, filename: str) -> str | None:
    if "account_id" in m:
        values = {clean_text(v).lower() for v in frame[m["account_id"]].tolist() if clean_text(v)}
        if len(values) == 1:
            return values.pop()
    for text in (preamble, filename):
        upi = UPI_RE.search(text or "")
        if upi:
            return upi.group(1).lower()
        acct = ACCOUNT_RE.search(text or "")
        if acct:
            return "acct:" + re.sub(r"[\s-]", "", acct.group(1)).lower()
    return None


def validate_plan(plan: dict[str, Any], columns: list[str]) -> dict[str, Any]:
    """Keep only known fields mapped to real, distinct columns; recompute mode and gaps.

    ``mode_override`` (set by the analyst, or by Gemini when the rules found no shape) wins over the
    automatically detected shape; the gaps are then computed for that shape.
    """
    mapping, used, dropped = {}, set(), []
    for field, col in (plan.get("mapping") or {}).items():
        if field in FIELD_HELP and col in columns and col not in used:
            mapping[field] = col
            used.add(col)
        elif col:
            dropped.append(f"{field} → {col}")
    mode, missing = decide_mode(mapping)
    override = plan.get("mode_override")
    if override in ("transfers", "statement"):
        mode, missing = override, missing_for(override, mapping)
    out = {**plan, "mapping": mapping, "mode": mode, "missing": list(missing)}
    if mode == "statement" and not clean_text(plan.get("statement_account")):
        out["missing"].append("statement account (whose statement is this?)")
    if dropped:
        out["warnings"] = list(out.get("warnings", [])) + ["Ignored invalid mappings: " + ", ".join(dropped)]
    out["ready"] = bool(mode) and not out["missing"]
    return out


def plan_from_request(requested: dict[str, Any], columns: list[str], base: dict[str, Any]) -> dict[str, Any]:
    """Apply an analyst-edited plan (from the review screen) on top of the automatic one."""
    mapping = requested.get("mapping")
    mapping = base.get("mapping", {}) if mapping is None else {k: v for k, v in mapping.items() if v}
    merged = {**base, "mapping": dict(mapping),
              "statement_account": clean_text(requested.get("statement_account") or base.get("statement_account")).lower()}
    if requested.get("mode") in ("transfers", "statement"):
        merged["mode_override"] = requested["mode"]
    merged["source"] = {f: ("you" if base.get("mapping", {}).get(f) != c else base.get("source", {}).get(f, "rule"))
                        for f, c in merged["mapping"].items()}
    return validate_plan(merged, columns)


def build_plan(sheet: str, info: dict[str, Any], filename: str, *, use_gemini: bool, statement_account: str = "") -> dict[str, Any]:
    frame: pd.DataFrame = info["frame"]
    columns = [str(c) for c in frame.columns]
    started = time.perf_counter()
    mapping = rule_mapping(columns)
    source = {f: "rule" for f in mapping}
    mode, missing = decide_mode(mapping)
    plan: dict[str, Any] = {"sheet": sheet, "mode": mode, "mapping": mapping, "source": source, "notes": [], "warnings": [],
                            "gemini": {"enabled": gemini_service.enabled(), "used": False}}
    plan["timings"] = {"rules_ms": round((time.perf_counter() - started) * 1000, 1)}

    if use_gemini and gemini_service.enabled() and (mode is None or missing):
        started = time.perf_counter()
        samples = [{c: clean_text(v) for c, v in row.items()} for row in frame.head(8).to_dict("records")]
        ai = gemini_service.suggest_plan(columns, samples, info.get("preamble", ""), filename, FIELD_HELP)
        plan["timings"]["gemini_ms"] = round((time.perf_counter() - started) * 1000, 1)
        plan["gemini"] = {"enabled": True, "used": ai.get("ok", False), "model": ai.get("model"), "provider": ai.get("provider"), "error": ai.get("error")}
        if ai.get("ok"):
            for field, col in ai.get("mapping", {}).items():
                if field in FIELD_HELP and field not in mapping and col in columns and col not in mapping.values():
                    mapping[field] = col
                    source[field] = "gemini"
            if ai.get("dataset_type") in ("transfers", "statement") and decide_mode(mapping)[0] is None:
                plan["mode_override"] = ai["dataset_type"]
            plan["notes"] += [f"AI: {n}" for n in ai.get("notes", [])][:6]
            plan["warnings"] += [f"AI: {w}" for w in ai.get("warnings", [])][:6]
            acct = (ai.get("statement_account") or "").strip()
            haystack = (info.get("preamble", "") + " " + filename + " " + " ".join(" ".join(map(str, r.values())) for r in samples)).lower()
            if acct and acct.lower() in haystack:
                plan["statement_account_ai"] = acct.lower()
            elif acct:
                plan["warnings"].append("AI suggested a statement account that does not appear in the file; ignored.")

    guessed = guess_statement_account(frame, mapping, info.get("preamble", ""), filename)
    plan["statement_account"] = (statement_account or plan.get("statement_account_ai") or guessed or "").strip().lower()
    plan["statement_account_source"] = "you" if statement_account else ("gemini" if plan.get("statement_account_ai") else ("file" if guessed else None))
    return validate_plan(plan, columns)


# --------------------------------------------------------------------------------------
# Row normalisation
# --------------------------------------------------------------------------------------

def signed_amount(value: Any) -> tuple[Decimal | None, int | None]:
    """Parse an amount and any sign / Dr / Cr marker. Returns (absolute amount, -1 out / +1 in / None)."""
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None, None
    if isinstance(value, (int, float, Decimal)) and not isinstance(value, bool):
        d = Decimal(str(value))
        return (abs(d).quantize(Decimal("0.01")), (-1 if d < 0 else None)) if d != 0 else (None, None)
    text = clean_text(value).upper()
    if not text or text in {"-", "--", "NIL", "NA", "N/A", "0", "0.00", "0.0"}:
        return None, None
    sign = None
    if re.search(r"\bDR\.?$", text):
        sign = -1
    elif re.search(r"\bCR\.?$", text):
        sign = 1
    text = re.sub(r"\b(DR|CR)\.?$", "", text)
    text = text.replace("₹", "").replace("INR", "").replace("RS.", "").replace("RS", "").replace(",", "").replace(" ", "")
    if text.startswith("(") and text.endswith(")"):
        text, sign = text[1:-1], -1
    if text.startswith("-"):
        text, sign = text[1:], -1
    elif text.startswith("+"):
        text, sign = text[1:], (sign or 1)
    try:
        d = Decimal(text)
    except InvalidOperation:
        raise ValueError(f"invalid amount: {clean_text(value)}")
    if d == 0:
        return None, None
    return abs(d).quantize(Decimal("0.01")), sign


def extract_counterparty(text: str, own: str | None = None) -> tuple[str | None, str | None]:
    t = clean_text(text)
    if not t:
        return None, None
    for match in UPI_RE.findall(t):
        if own and match.lower() == own.lower():
            continue
        return match.lower(), "UPI ID found in narration"
    upper = t.upper()
    if re.search(r"\bATM\b|CASH\s*WDL|CASH\s*WITHDRAW|\bATW\b|\bNWD\b|\bCWDR\b", upper):
        return "cash:atm-withdrawal", "cash withdrawal in narration"
    if re.search(r"CASH\s*DEP", upper):
        return "cash:deposit", "cash deposit in narration"
    if re.search(r"INTEREST|\bINT\.?\s*(PD|PAID|CR)\b", upper):
        return "bank:interest", "interest entry"
    if re.search(r"CHARGES?|\bCHG\b|\bFEE\b|\bGST\b|\bSMS\b", upper):
        return "bank:charges", "bank charge entry"
    for token in re.split(r"[/\-|:*@]+", t):
        letters = re.sub(r"[^A-Za-z ]", " ", token)
        words = [w for w in letters.upper().split() if w not in STOP and len(w) > 1]
        if words and len(" ".join(words)) >= 3:
            return "name:" + ".".join(w.lower() for w in words)[:60], "name found in narration"
    slug = re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")[:40]
    return ("unidentified:" + slug if slug else None), "narration could not be parsed"


def _cell(row: dict[str, Any], m: dict[str, str], field: str) -> Any:
    col = m.get(field)
    return row.get(col) if col else None


def _row_timestamp(row: dict[str, Any], m: dict[str, str]) -> tuple[datetime, bool, list[str]]:
    repairs: list[str] = []
    if m.get("timestamp") and clean_text(_cell(row, m, "timestamp")):
        dt, amb = parse_timestamp_ex(_cell(row, m, "timestamp"))
        return dt, amb, repairs
    d, t = _cell(row, m, "date"), _cell(row, m, "time")
    if not clean_text(d) and clean_text(t):
        dt, amb = parse_timestamp_ex(t)  # a "time" column holding full date-times
        return dt, amb, repairs
    if not clean_text(d):
        raise ValueError("date / timestamp is empty")
    if isinstance(d, (pd.Timestamp, datetime, date_type)) and isinstance(t, (time_type, datetime, pd.Timestamp)):
        tt = t.time() if isinstance(t, (datetime, pd.Timestamp)) else t
        dd = d.date() if isinstance(d, (datetime, pd.Timestamp)) else d
        value: Any = datetime.combine(dd, tt)
    elif clean_text(t):
        dpart = d.strftime("%Y-%m-%d") if isinstance(d, (pd.Timestamp, datetime, date_type)) else clean_text(d)
        tpart = t.strftime("%H:%M:%S") if isinstance(t, (time_type, datetime, pd.Timestamp)) else clean_text(t)
        value = f"{dpart} {tpart}"
    else:
        value = d
        repairs.append("date only: time unknown, set to 00:00 IST")
    dt, amb = parse_timestamp_ex(value)
    return dt, amb, repairs


def _slug_name(name: str) -> str:
    return "name:" + re.sub(r"[^a-z0-9]+", ".", clean_text(name).lower()).strip(".")[:60]


def normalize_with_plan(row: dict[str, Any], plan: dict[str, Any], row_no: int, sheet: str,
                        occurrences: dict[str, int]) -> NormalizedRow | None:
    """Normalise one row. Returns None for blank / summary rows that carry no transaction."""
    m = plan["mapping"]
    money_cells = [_cell(row, m, f) for f in ("amount", "debit_amount", "credit_amount")]
    if not any(clean_text(v) for v in money_cells):
        has_date = any(clean_text(_cell(row, m, f)) for f in ("timestamp", "date"))
        label = " ".join(clean_text(_cell(row, m, f)) for f in ("description", "counterparty", "sender_id")).lower()
        if not has_date or re.search(r"opening|closing|balance|total|brought forward|carried forward|statement summary", label):
            return None  # blank, opening/closing balance or summary row
        raise ValueError("no amount on this row")

    repairs: list[str] = []
    timestamp, ambiguous, ts_repairs = _row_timestamp(row, m)
    repairs += ts_repairs
    if ambiguous:
        repairs.append("ambiguous day/month read as " + ("DD/MM" if dayfirst_default() else "MM/DD"))

    if plan["mode"] == "statement":
        own = clean_text(plan.get("statement_account")).lower()
        if not own:
            raise ValueError("statement account is not set")
        debit, _ = signed_amount(_cell(row, m, "debit_amount")) if m.get("debit_amount") else (None, None)
        credit, _ = signed_amount(_cell(row, m, "credit_amount")) if m.get("credit_amount") else (None, None)
        if debit and credit:
            raise ValueError("row has both a debit and a credit amount")
        if debit or credit:
            amount, direction = (debit, -1) if debit else (credit, 1)
        else:
            amount, direction = signed_amount(_cell(row, m, "amount"))
            marker = clean_text(_cell(row, m, "direction")).upper().strip(".")
            if marker in OUT_WORDS:
                direction = -1
            elif marker in IN_WORDS:
                direction = 1
            if amount is None:
                raise ValueError("amount is empty")
            if direction is None:
                raise ValueError("cannot tell if money went in or out (no debit/credit column or Dr/Cr marker)")
        counterparty = clean_text(_cell(row, m, "counterparty"))
        if counterparty:
            other = counterparty.lower() if UPI_RE.fullmatch(counterparty) else _slug_name(counterparty)
            if not UPI_RE.fullmatch(counterparty):
                repairs.append("counterparty ID derived from name")
        else:
            other, how = extract_counterparty(clean_text(_cell(row, m, "description")), own)
            if not other:
                raise ValueError("no counterparty: narration is empty")
            repairs.append(f"counterparty derived: {how}")
        sender, receiver = (own, other) if direction == -1 else (other, own)
    else:
        sender = clean_text(_cell(row, m, "sender_id"))
        receiver = clean_text(_cell(row, m, "receiver_id"))
        if not sender and clean_text(_cell(row, m, "sender_name")):
            sender = _slug_name(_cell(row, m, "sender_name")); repairs.append("sender ID derived from name")
        if not receiver and clean_text(_cell(row, m, "receiver_name")):
            receiver = _slug_name(_cell(row, m, "receiver_name")); repairs.append("receiver ID derived from name")
        amount, _sign = signed_amount(_cell(row, m, "amount"))
        if amount is None:
            raise ValueError("amount is empty or zero")
    if not sender:
        raise ValueError("sender is missing")
    if not receiver:
        raise ValueError("receiver is missing")
    if sender == receiver:
        raise ValueError("sender and receiver are identical")

    currency = clean_text(_cell(row, m, "currency")).upper() or "INR"
    if len(currency) != 3:
        currency = "INR"; repairs.append("normalized currency to INR")
    core = f"{sender}|{receiver}|{amount}|{currency}|{timestamp.isoformat()}"
    occurrence = occurrences.get(core, 0)
    occurrences[core] = occurrence + 1
    fingerprint = content_fingerprint(sender, receiver, amount, currency, timestamp, occurrence)
    import hashlib
    supplied_id = clean_text(_cell(row, m, "transaction_id"))
    transaction_id = supplied_id or "FP-" + fingerprint[:20]
    event_id = clean_text(_cell(row, m, "event_id"))
    if not event_id:
        seed = f"{transaction_id}|{fingerprint}" if supplied_id else fingerprint
        event_id = "EVT-" + hashlib.sha256(seed.encode()).hexdigest()[:32].upper()
    source_ref = clean_text(_cell(row, m, "source_record_ref")) or "FP:" + fingerprint
    value_repairs = [r for r in repairs if not r.startswith("derived ")]
    return NormalizedRow(
        transaction_id=transaction_id[:128], event_id=event_id[:128], sender_id=sender[:255], receiver_id=receiver[:255],
        amount=amount, currency=currency, timestamp=timestamp, source_record_ref=source_ref[:255],
        quality="normalized" if value_repairs else "observed", repairs=repairs, sheet=sheet, row_no=row_no, fingerprint=fingerprint)


def preview_rows(frame: pd.DataFrame, plan: dict[str, Any], sheet: str, header_row: int, limit: int = 8) -> list[dict[str, Any]]:
    out, occ = [], {}
    if not plan.get("mode"):
        return out
    for i, (_, row) in enumerate(frame.head(limit).iterrows()):
        row_no = header_row + 2 + i
        try:
            n = normalize_with_plan(row.to_dict(), plan, row_no, sheet, occ)
            if n is None:
                out.append({"row": row_no, "ok": True, "skipped": True})
                continue
            out.append({"row": row_no, "ok": True, "sender": n.sender_id, "receiver": n.receiver_id, "amount": str(n.amount),
                        "timestamp": n.timestamp.isoformat(), "reference": n.transaction_id, "repairs": n.repairs, "quality": n.quality})
        except Exception as exc:  # noqa: BLE001 - shown to the analyst as a row error
            out.append({"row": row_no, "ok": False, "error": str(exc)[:200]})
    return out
