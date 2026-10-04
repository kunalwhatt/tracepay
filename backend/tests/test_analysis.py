"""rules-v1, graph and account-summary tests.

Several tests mirror the case studies in the Trace.Pay project book (sections 71-77), so they
double as the evaluation harness for the research write-up. Run with: pytest backend/tests
"""
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from app.analysis import Movement, account_summary, assemble_graph, daily_series, evaluate_risk, max_burst

IST = timezone(timedelta(hours=5, minutes=30))
T0 = datetime(2026, 10, 3, 9, 41, tzinfo=IST)


def tx(ref, sender, receiver, amount, minutes, kind="observed", status="OBSERVED", **prov):
    return Movement(key=f"{kind}:{ref}", ref=ref, sender=sender, receiver=receiver, amount=Decimal(str(amount)),
                    at=T0 + timedelta(minutes=minutes), kind=kind, status=status, provenance=prov)


def mule_network():
    """Case study 71: V1 pays TP-A, six more senders converge, TP-A fans out, TP-B moves on."""
    rows = [tx("V1-A", "V1", "TP-A", 25000, 0)]
    rows += [tx(f"S{i}-A", f"S{i}", "TP-A", 4000 + i * 100, 2 + i * 3) for i in range(6)]
    rows += [tx("A-B", "TP-A", "TP-B", 12000, 12), tx("A-C", "TP-A", "TP-C", 9000, 15), tx("A-D", "TP-A", "TP-D", 8000, 18)]
    rows += [tx("B-E", "TP-B", "TP-E", 7000, 40)]
    return rows


def test_mule_network_triggers_review_with_evidence():
    result = evaluate_risk("TP-A", mule_network(), T0 + timedelta(hours=1))
    assert result["level"] == "review"
    codes = {e["code"] for e in result["evidence"]}
    assert codes == {"INBOUND_BREADTH", "RAPID_ONWARD"}
    rapid = next(e for e in result["evidence"] if e["code"] == "RAPID_ONWARD")
    assert rapid["first_incoming"] == "V1-A" and rapid["first_onward"] == "A-B"
    assert rapid["elapsed_minutes"] == 12.0
    inbound = next(e for e in result["evidence"] if e["code"] == "INBOUND_BREADTH")
    assert inbound["observed"] == 7 and len(inbound["records"]) == 7


def test_merchant_false_positive_is_caution_not_review():
    """Case study 72: many customers, a few suppliers, no rapid onward movement."""
    rows = [tx(f"C{i}", f"CUST{i}", "TP-MERCHANT", 300, i) for i in range(80)]
    rows += [tx(f"P{i}", "TP-MERCHANT", f"SUP{i}", 5000, 600 + i * 30) for i in range(3)]
    result = evaluate_risk("TP-MERCHANT", rows, T0 + timedelta(hours=20))
    assert result["level"] == "caution"
    assert [e["code"] for e in result["evidence"]] == ["INBOUND_BREADTH"]


def test_insufficient_information_when_no_records():
    result = evaluate_risk("TP-NOBODY", mule_network(), T0 + timedelta(hours=1))
    assert result["level"] == "insufficient_information" and result["observed_count"] == 0


def test_window_is_anchored_to_as_of_not_wall_clock():
    rows = mule_network()
    assert evaluate_risk("TP-A", rows, T0 + timedelta(hours=1))["level"] == "review"
    assert evaluate_risk("TP-A", rows, T0 + timedelta(days=3))["level"] == "insufficient_information"


def test_failed_ledger_attempts_never_count():
    """Case study 76 boundary: a FAILED internal transfer is not value movement."""
    rows = [tx(f"F{i}", f"U{i}", "TP-X", 100, i, kind="ledger", status="FAILED") for i in range(9)]
    assert evaluate_risk("TP-X", rows, T0 + timedelta(hours=1))["level"] == "insufficient_information"


def test_graph_levels_follow_money_left_to_right():
    graph = assemble_graph("TP-A", mule_network(), max_hops=3)
    level = {n["id"]: n["level"] for n in graph["nodes"]}
    assert level["TP-A"] == 0 and level["V1"] == -1 and level["TP-B"] == 1 and level["TP-E"] == 2
    root = next(n for n in graph["nodes"] if n["is_root"])
    assert root["unique_senders"] == 7 and root["unique_receivers"] == 3
    assert graph["summary"]["edge_count"] == 11


def test_missing_middle_hop_is_not_invented():
    """Case study 73: only the observed edges exist; nothing connects across the gap."""
    rows = [tx("V2-X", "V2", "TP-X", 18000, 0), tx("X-Y", "TP-X", "TP-Y", 10000, 102)]
    graph = assemble_graph("TP-X", rows, max_hops=3)
    assert {(e["source"], e["target"]) for e in graph["edges"]} == {("V2", "TP-X"), ("TP-X", "TP-Y")}
    node = next(n for n in graph["nodes"] if n["id"] == "TP-X")
    assert node["observed_flow_difference"] == "8000"


def test_multigraph_keeps_parallel_transfers_and_evidence_states():
    rows = [tx("T1", "A", "B", 5000, 0), tx("T2", "A", "B", 2000, 5, provenance_status="normalized"),
            tx("TB1", "A", "B", 100, 6, kind="ledger", status="SUCCESS"),
            tx("TB2", "A", "B", 900, 7, kind="ledger", status="FAILED")]
    graph = assemble_graph("A", rows, max_hops=1)
    states = [e["evidence_state"] for e in graph["edges"]]
    assert states == ["observed", "observed_normalized", "ledger_confirmed", "failed_attempt"]
    a = next(n for n in graph["nodes"] if n["id"] == "A")
    assert a["out_total"] == "7100" and a["failed_attempts"] == 1


def test_account_summary_and_burst():
    summary = account_summary("TP-A", mule_network())
    assert summary["in_count"] == 7 and summary["out_count"] == 3
    assert summary["unique_senders"] == 7 and summary["max_events_in_one_hour"] == 10
    assert summary["rules_at_last_activity"]["level"] == "review"
    assert max_burst([T0, T0 + timedelta(minutes=30), T0 + timedelta(hours=3)]) == 2


def test_daily_series_is_data_anchored():
    series = daily_series(mule_network(), end=None, days=7)
    assert len(series) == 7 and series[-1]["date"] == "2026-10-03" and series[-1]["count"] == 11


def test_behaviour_profile_is_explainable():
    s = account_summary("TP-A", mule_network())
    assert sum(h["in"] + h["out"] for h in s["hourly"]) == 10
    assert [r["triggered"] for r in s["rule_table"]] == [True, False, True]
    assert s["rule_table"][0]["observed"] == "7 senders"
    assert s["counterparties"][0]["account"] in {"TP-B", "V1"} and len(s["counterparties"]) == 10
    assert "review" in s["plain_summary"] and "fast onward movement" in s["plain_summary"]
    assert sum(b["in"] for b in s["amount_buckets"]) == 7
