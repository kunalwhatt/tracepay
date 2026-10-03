"""Ingestion normalization tests (pure functions, no database)."""
from pathlib import Path

from app.ingestion_service import deterministic_mapping, normalize_row, parse_timestamp_ex, read_upload

SAMPLES = Path(__file__).resolve().parents[2] / "data" / "samples"
M = {"sender_id": "s", "receiver_id": "r", "amount": "a", "timestamp": "t"}


def test_indian_day_first_dates():
    dt, ambiguous = parse_timestamp_ex("03/10/2026 10:00")
    assert (dt.month, dt.day, ambiguous) == (10, 3, True)
    dt, ambiguous = parse_timestamp_ex("30/09/2026 10:20")
    assert (dt.month, dt.day, ambiguous) == (9, 30, False)


def test_iso_dates_are_never_day_first():
    dt, _ = parse_timestamp_ex("2026-03-10 09:00")
    assert (dt.month, dt.day) == (3, 10)


def test_naive_times_default_to_ist():
    dt, _ = parse_timestamp_ex("2026-10-03 10:00")
    assert (dt.hour, dt.minute) == (4, 30)


def test_reupload_without_ids_is_idempotent():
    """Case study 74: the same file twice must produce identical identities."""
    row = {"s": "A", "r": "B", "a": "500", "t": "2026-10-01 10:00"}
    first = normalize_row(row, M, 2, "csv", {})
    second = normalize_row(row, M, 2, "csv", {})
    assert (first.transaction_id, first.event_id, first.source_record_ref) == (second.transaction_id, second.event_id, second.source_record_ref)


def test_identical_rows_inside_one_file_stay_distinct():
    row = {"s": "A", "r": "B", "a": "500", "t": "2026-10-01 10:00"}
    seen = {}
    assert normalize_row(row, M, 2, "csv", seen).transaction_id != normalize_row(row, M, 3, "csv", seen).transaction_id


def test_distinct_supplied_ids_with_same_content_are_not_duplicates():
    mapping = {**M, "transaction_id": "id"}
    a = normalize_row({"id": "T1", "s": "A", "r": "B", "a": "5", "t": "2026-10-01 10:00"}, mapping, 2, "x", {})
    b = normalize_row({"id": "T2", "s": "A", "r": "B", "a": "5", "t": "2026-10-01 10:00"}, mapping, 2, "y", {})
    assert a.event_id != b.event_id


def test_ambiguous_date_marks_row_normalized():
    row = normalize_row({"s": "A", "r": "B", "a": "5", "t": "03/10/2026 10:00"}, M, 2, "csv", {})
    assert row.quality == "normalized" and any("ambiguous" in r for r in row.repairs)


def test_self_transfer_rejected():
    try:
        normalize_row({"s": "A", "r": "A", "a": "5", "t": "2026-10-01"}, M, 2, "csv", {})
    except ValueError as exc:
        assert "identical" in str(exc)
    else:
        raise AssertionError("expected rejection")


def test_bundled_samples_normalize():
    for name in ("messy_transactions.csv", "messy_transactions.xlsx"):
        path = SAMPLES / name
        for sheet, frame in read_upload(path.name, path.read_bytes()).items():
            mapping = deterministic_mapping([str(c) for c in frame.columns])
            seen = {}
            rows = [normalize_row(r.to_dict(), mapping, i, sheet, seen) for i, (_, r) in enumerate(frame.iterrows(), start=2)]
            assert len(rows) == 5
            assert rows[1].timestamp.day == 30  # "30/09/2026 10:20"


# ---- Trace.Pay ID rules -------------------------------------------------------------
from app.ids import normalize_tracepay_id


def test_tracepay_ids_are_name_at_tracepay_only():
    assert normalize_tracepay_id("Meera.Iyer@TracePay") == "meera.iyer@tracepay"
    assert normalize_tracepay_id("  meera.iyer ") == "meera.iyer@tracepay"
    assert normalize_tracepay_id("upi://pay?pa=meera.iyer@tracepay&pn=Meera") == "meera.iyer@tracepay"
    for bad in ("meera@okhdfc", "meera@tracepay.evil", "@tracepay", ".meera@tracepay", "me era@tracepay", "upi://pay?pa=x@ybl"):
        try:
            normalize_tracepay_id(bad)
        except ValueError:
            continue
        raise AssertionError(f"accepted {bad}")
