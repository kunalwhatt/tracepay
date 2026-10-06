"""TraceFlow, TraceSense/TraceScore, TraceRank and TraceBench on the real Pranay day (4 Oct 2026, IST)."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from app.analysis import Movement
from app import traceflow, tracesense, tracerank, tracebench

IST = timezone(timedelta(hours=5, minutes=30))
P = "pranay.kunta@tracepay"
K = "kunal.test@tracepay"
H = "gorantla.sai.hemanth@tracepay"


def at(hm):
    return datetime(2026, 10, 4, int(hm[:2]), int(hm[3:]), tzinfo=IST)


def pranay_day():
    rows = [("t1", "18:40", "test.payer1@okaxis", P, 4500, "observed"), ("t2", "18:44", "test.payer2@oksbi", P, 7200, "observed"),
            ("t3", "18:48", "test.payer3@ybl", P, 3800, "observed"), ("t4", "18:52", "test.payer4@okhdfc", P, 9100, "observed"),
            ("t5", "18:58", P, "test.onward1@tracepay", 15000, "observed"),
            ("b01", "19:00", K, P, 1000, "ledger"), ("b02", "19:07", K, P, 5555, "ledger"), ("b03", "20:00", P, K, 2000, "ledger"),
            ("b04", "20:01", P, H, 2000, "ledger"), ("b05", "20:08", H, P, 250, "ledger")]
    small = [("20:11", K, 500), ("20:11", H, 500), ("20:11", K, 500), ("20:11", K, 500), ("20:12", H, 6500), ("20:12", K, 200),
             ("20:12", K, 500), ("20:13", K, 100), ("20:13", H, 100), ("20:13", K, 100), ("20:13", K, 100), ("20:14", H, 50),
             ("20:14", H, 25), ("20:15", H, 25)]
    rows += [(f"s{i:02d}", t, s, P, a, "ledger") for i, (t, s, a) in enumerate(small)]
    return [Movement(key=k, ref=k.upper(), sender=s, receiver=r, amount=Decimal(a), at=at(t), kind=kind,
                     status="SUCCESS" if kind == "ledger" else "OBSERVED") for k, t, s, r, a, kind in rows]


def test_causal_tracing_removes_impossible_links():
    reach = traceflow.causal_reach(pranay_day(), K, since=at("19:00"))
    assert "t5" not in reach["forward_edges"]  # Kunal's money cannot be in onward1 (paid 2 minutes earlier)
    assert "test.onward1@tracepay" not in reach["forward_accounts"]
    assert {"b03", "b04"} <= set(reach["forward_edges"])
    hem = traceflow.causal_reach(pranay_day(), H, since=at("20:08"))
    assert K not in hem["forward_accounts"]  # Hemanth paid in after Pranay's last outgoing transfer
    assert traceflow.causal_reach(pranay_day(), P)["impossible_edges"] == []


def test_attribution_fifo_and_proportional_match_hand_calculation():
    day = pranay_day()
    fifo = traceflow.attribute(day, "t1", "fifo")
    assert fifo["holdings"] == {"test.onward1@tracepay": "4500.00"}
    p4 = traceflow.attribute(day, "t4", "fifo")
    # payer4's money left Pranay (₹1,500 to Kunal, ₹2,000 to Hemanth) and came back in their small payments
    assert p4["edge_flow"]["b03"] == "1500.00" and p4["edge_flow"]["b04"] == "2000.00"
    assert p4["holdings"] == {P: "9100.00"}
    prop = traceflow.attribute(day, "t1", "proportional")
    assert abs(Decimal(prop["holdings"]["test.onward1@tracepay"]) - Decimal("2743.90")) < Decimal("0.05")
    both = traceflow.attribute_all(day, "t1")
    assert both["disagreement"]["fifo_vs_proportional"] > 0.3


def test_hold_list_golden_hour_and_bottleneck():
    day = pranay_day()
    a = traceflow.attribute(day, "t4", "fifo")
    cut = traceflow.bottlenecks(day, a)
    holds = traceflow.hold_list(a, cut)
    assert holds[0]["account"] == P and holds[0]["traced_funds_now"] == "9100.00"
    gh = traceflow.golden_hour(a, now=at("20:30"))
    assert gh["recoverable_amount"] == "9100.00" and gh["exited_amount"] == "0.00" and not gh["within_golden_hour"]
    cash = [Movement(key="x1", ref="X1", sender="v@oksbi", receiver="m@tracepay", amount=Decimal(10000), at=at("10:00"), kind="observed"),
            Movement(key="x2", ref="X2", sender="m@tracepay", receiver="cash:atm-withdrawal", amount=Decimal(9000), at=at("10:20"), kind="observed")]
    g2 = traceflow.golden_hour(traceflow.attribute(cash, "x1"), now=at("10:40"))
    assert g2["exited_amount"] == "9000.00" and g2["minutes_to_first_exit"] == 20.0


def test_peel_chain_detected():
    chain = [Movement(key=f"p{i}", ref=f"P{i}", sender=f"a{i}", receiver=f"a{i + 1}", amount=Decimal(a), at=at(f"10:{i * 5:02d}"), kind="observed")
             for i, a in enumerate([50000, 46000, 41000, 37000])]
    found = traceflow.peel_chains(chain)
    assert found and len(found[0]["keys"]) == 4


def test_tracescore_explains_pranay():
    day = pranay_day()
    net = tracesense.network_signals(day)
    s = tracesense.trace_score(P, day, as_of=at("20:30"), network=net)
    codes = {c["code"] for c in s["contributions"]}
    assert {"INBOUND_BREADTH", "RAPID_ONWARD", "STRUCTURING", "ROUND_TRIP", "FAN_IN_OUT"} <= codes
    assert s["band"] in ("review", "high_review") and s["score"] >= 50
    assert any("₹500×" in c["detail"] for c in s["contributions"] if c["code"] == "STRUCTURING")
    assert s["counterfactuals"] and 0 < s["confidence"] <= 1
    k = tracesense.trace_score(K, day, as_of=at("20:30"), network=net)
    assert (k["score"] or 0) < s["score"]


def test_signal_helpers():
    vc_moves = [Movement(key=f"v{i}", ref=f"V{i}", sender=f"stranger{i}", receiver="m", amount=Decimal(999), at=at(f"10:{i:02d}"), kind="observed") for i in range(6)]
    assert tracesense.victim_convergence("m", vc_moves, at("11:00"))["first_time_share"] == 1.0
    esc = [Movement(key=f"e{i}", ref=f"E{i}", sender="vic", receiver="m", amount=Decimal(a), at=at(f"1{i}:00"), kind="observed") for i, a in enumerate([200, 1000, 5000])]
    assert tracesense.escalation("m", esc)[0]["growth"] == 25.0
    adj = {"a": {"b", "c"}, "b": {"a", "c"}, "c": {"a", "b", "d"}, "d": {"c"}}
    assert tracesense.k_core(adj) == {"a": 2, "b": 2, "c": 2, "d": 1}
    bc = tracesense.betweenness({"a": {"b"}, "b": {"c"}, "c": set()})
    assert bc["b"] > 0 and bc["a"] == 0
    comm = tracesense.louvain({("a", "b"): 5, ("b", "c"): 5, ("a", "c"): 5, ("d", "e"): 5, ("e", "f"): 5, ("d", "f"): 5, ("c", "d"): 0.1})
    assert comm["a"] == comm["b"] == comm["c"] != comm["d"] == comm["e"] == comm["f"]
    rows = {f"n{i}": [1.0, 1.0] for i in range(30)}; rows["odd"] = [40.0, 50.0]
    iso = tracesense.isolation_scores(rows)
    assert iso["odd"] > max(v for k, v in iso.items() if k != "odd")


def test_tracerank_spreads_from_seeds_and_respects_feedback():
    day = pranay_day()
    r = tracerank.trace_rank(day, {"test.payer1@okaxis": 1.0})
    names = [x["account"] for x in r["ranking"]]
    assert names[0] == P and r["ranking"][0]["path"][0] == "test.payer1@okaxis"
    cleared = tracerank.trace_rank(day, {"test.payer1@okaxis": 1.0}, cleared={P})
    assert P not in [x["account"] for x in cleared["ranking"]]


def test_tracebench_world_and_evaluation():
    world = tracebench.generate_world(normal_users=30, merchants=3, rings=2)
    res = tracebench.evaluate(world)
    score, core = res["detectors"]["TraceScore (watch or above)"], res["detectors"]["TraceSense Core (caution or above)"]
    assert score["f1"] >= core["f1"] and score["recall"] >= 0.8 and score["false_positives"] <= core["false_positives"]
    assert res["score_by_role"]["collector"] > res["score_by_role"]["merchant"] and res["score_by_role"]["layer"] > res["score_by_role"]["normal"]
    assert tracebench.trace_recall(world) > 0.8
