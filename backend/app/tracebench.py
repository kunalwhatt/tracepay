"""TraceBench: a synthetic fraud world with ground truth, and the experiments that measure Trace.Pay.

The generator builds ordinary users, merchants (many small repeat customers) and mule rings
(victims → collector → layers → cash-out), including task-scam escalation. Every account has a
true role, so detectors can be scored: precision, recall, F1, false positives and time-to-flag.
Robustness curves vary mule behaviour; data-gap experiments drop records and corrupt dates.
"""
from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from . import tracesense
from .analysis import Movement, evaluate_risk
from .traceflow import attribute

IST = timezone(timedelta(hours=5, minutes=30))
MULE_ROLES = {"collector", "layer", "cashout"}


def generate_world(*, seed: int = 42, normal_users: int = 60, merchants: int = 6, rings: int = 4, victims_per_ring: int = 7,
                   layers: int = 2, mule_delay_min: float = 12, split: int = 2, start: datetime | None = None) -> dict:
    rng = random.Random(seed)
    start = start or datetime(2026, 10, 1, 9, 0, tzinfo=IST)
    moves: list[Movement] = []
    roles: dict[str, str] = {}
    victim_payments: list[dict] = []
    counter = [0]

    def mv(s, r, amount, at, kind="observed"):
        counter[0] += 1
        m = Movement(key=f"b{counter[0]}", ref=f"BENCH-{counter[0]:05d}", sender=s, receiver=r, amount=Decimal(str(round(amount, 2))),
                     at=at, kind=kind, provenance={"source_id": "tracebench", "provenance_status": "observed", "source_record_ref": f"r{counter[0]}"})
        moves.append(m)
        return m
    people = [f"user{i:03d}@okaxis" for i in range(normal_users)]
    for p in people:
        roles[p] = "normal"
    for i in range(merchants):
        shop = f"shop{i:02d}@tracepay"; roles[shop] = "merchant"
        regulars = rng.sample(people, 12)
        for day in range(3):
            for c in rng.sample(regulars, 9):
                mv(c, shop, rng.choice([40, 60, 120, 180, 250]), start + timedelta(days=day, minutes=rng.randint(0, 600)))
        mv(shop, f"supplier{i:02d}@okhdfc", 3000, start + timedelta(days=2, hours=11)); roles[f"supplier{i:02d}@okhdfc"] = "normal"
    for _ in range(len(people) * 3):  # ordinary peer payments
        a, b = rng.sample(people, 2)
        mv(a, b, rng.choice([100, 250, 500, 1200, 2000]), start + timedelta(days=rng.randint(0, 2), minutes=rng.randint(0, 900)))
    for r in range(rings):
        collector = f"ring{r}.collect@tracepay"; roles[collector] = "collector"
        t0 = start + timedelta(days=rng.randint(0, 2), hours=rng.randint(1, 8))
        total = 0.0
        for v in range(victims_per_ring):
            victim = f"victim{r}{v}@oksbi"; roles[victim] = "victim"
            at = t0 + timedelta(minutes=v * rng.randint(2, 5))
            if v == 0:  # task-scam escalation from the first victim
                for k, amt in enumerate([200, 1000, 5000]):
                    m = mv(victim, collector, amt, at - timedelta(hours=6 - 2 * k)); total += amt
            amt = rng.choice([4500, 7200, 9100, 12500, 19999, 25000])
            m = mv(victim, collector, amt, at); total += amt
            victim_payments.append({"key": m.key, "ring": r, "amount": amt})
        level, holders = [collector], []
        pot = total * 0.92
        t = t0 + timedelta(minutes=victims_per_ring * 3 + mule_delay_min)
        for depth in range(layers):
            nxt = []
            for h in level:
                for s in range(split):
                    acct = f"ring{r}.l{depth}{len(nxt)}@tracepay"; roles[acct] = "layer"
                    mv(h, acct, pot / (len(level) * split), t + timedelta(minutes=s)); nxt.append(acct)
            level = nxt; t += timedelta(minutes=mule_delay_min)
        cash = f"cash:atm-withdrawal-ring{r}"; roles[cash] = "cashout"
        for h in level:
            mv(h, cash, pot / len(level) * 0.98, t)
    for p in people:
        roles.setdefault(p, "normal")
    return {"movements": moves, "roles": roles, "victim_payments": victim_payments, "ring_count": rings}


def _metrics(flags: dict[str, bool], roles: dict[str, str]) -> dict:
    scored = {a: f for a, f in flags.items() if roles.get(a) not in ("victim", "cashout")}
    tp = sum(1 for a, f in scored.items() if f and roles[a] in MULE_ROLES)
    fp = sum(1 for a, f in scored.items() if f and roles[a] not in MULE_ROLES)
    fn = sum(1 for a, f in scored.items() if not f and roles[a] in MULE_ROLES)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"true_positives": tp, "false_positives": fp, "false_negatives": fn, "precision": round(precision, 3),
            "recall": round(recall, 3), "f1": round(f1, 3)}


def evaluate(world: dict) -> dict:
    moves, roles = world["movements"], world["roles"]
    accounts = [a for a in roles if any(a in (m.sender, m.receiver) for m in moves)]
    network = tracesense.network_signals(moves)
    core_flags, core_review, score_flags, score_review, anomaly_flags, ttf_core, ttf_score = {}, {}, {}, {}, {}, [], []
    burst_start = {}
    for vp in world["victim_payments"]:
        m = next((x for x in moves if x.key == vp["key"]), None)
        if m:
            burst_start[m.receiver] = min(burst_start.get(m.receiver, m.at), m.at)
    scores = {}
    for a in accounts:
        mine = [m for m in moves if a in (m.sender, m.receiver)]
        last = max(m.at for m in mine)
        core = evaluate_risk(a, moves, last)
        core_flags[a] = core["level"] in ("review", "caution")
        core_review[a] = core["level"] == "review"
        ts = tracesense.trace_score(a, moves, as_of=last, network=network)
        scores[a] = ts["score"] or 0
        score_flags[a] = (ts["score"] or 0) >= 25
        score_review[a] = (ts["score"] or 0) >= 50
        anomaly_flags[a] = network.get(a, {}).get("anomaly", {}).get("score", 0) >= 0.65
        if roles[a] == "collector" and a in burst_start:
            first_in = burst_start[a]  # first payment of the scam burst
            for m in sorted((x for x in mine if x.at >= first_in), key=lambda x: x.at):
                if evaluate_risk(a, moves, m.at)["level"] in ("review", "caution"):
                    ttf_core.append((m.at - first_in).total_seconds() / 60); break
            for m in sorted((x for x in mine if x.at >= first_in), key=lambda x: x.at):
                if (tracesense.trace_score(a, moves, as_of=m.at, network=network)["score"] or 0) >= 25:
                    ttf_score.append((m.at - first_in).total_seconds() / 60); break
    def avg(x): return round(sum(x) / len(x), 1) if x else None
    return {"accounts": len(accounts), "mules": sum(1 for a in accounts if roles[a] in MULE_ROLES),
            "detectors": {"TraceSense Core (caution or above)": {**_metrics(core_flags, roles), "minutes_to_flag": avg(ttf_core)},
                          "TraceScore (watch or above)": {**_metrics(score_flags, roles), "minutes_to_flag": avg(ttf_score)},
                          "TraceSense Core (review)": _metrics(core_review, roles),
                          "TraceScore (review or above)": _metrics(score_review, roles),
                          "Anomaly only": _metrics(anomaly_flags, roles)},
            "score_by_role": {role: round(sum(scores[a] for a in accounts if roles[a] == role) / max(1, sum(1 for a in accounts if roles[a] == role)), 1)
                              for role in sorted({roles[a] for a in accounts})}}


def trace_recall(world: dict) -> float:
    """Share of victim money that attribution (proportional) follows to the true cash-out."""
    moves, roles = world["movements"], world["roles"]
    got, total = 0.0, 0.0
    for vp in world["victim_payments"]:
        if not any(m.key == vp["key"] for m in moves):
            continue
        res = attribute(moves, vp["key"], "proportional")
        total += vp["amount"]
        got += sum(float(v) for a, v in res["holdings"].items() if roles.get(a) == "cashout")
    return round(got / total, 3) if total else 0.0


def robustness(seed: int = 42, delays=(5, 15, 30, 45, 60, 90)) -> list[dict]:
    rows = []
    for d in delays:
        res = evaluate(generate_world(seed=seed, mule_delay_min=d, normal_users=40, rings=3))
        rows.append({"mule_delay_minutes": d, **{k: v["recall"] for k, v in res["detectors"].items()}})
    return rows


def data_gaps(seed: int = 42, drops=(0.0, 0.1, 0.2, 0.3, 0.4)) -> list[dict]:
    rows = []
    for p in drops:
        world = generate_world(seed=seed, normal_users=40, rings=3)
        rng = random.Random(seed + int(p * 100))
        kept = [m for m in world["movements"] if rng.random() >= p]
        world = {**world, "movements": kept}
        res = evaluate(world)
        rows.append({"records_dropped": p, "trace_recall": trace_recall(world),
                     **{k: v["recall"] for k, v in res["detectors"].items()}})
    return rows


def run(seed: int = 42, quick: bool = False) -> dict:
    world = generate_world(seed=seed)
    out = {"world": {"accounts": len(world["roles"]), "transfers": len(world["movements"]), "rings": world["ring_count"]},
           "evaluation": evaluate(world), "trace_recall": trace_recall(world)}
    if not quick:
        out["robustness"] = robustness(seed)
        out["data_gaps"] = data_gaps(seed)
    out["notes"] = ["Synthetic data with known roles. Results show relative strengths, not real-world accuracy.",
                    "Victims and cash-out points are excluded from detection scoring."]
    return out
