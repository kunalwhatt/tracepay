"""Pure analysis functions for Trace.Pay.

Nothing in this module touches the database, so every rule and graph computation can be
unit-tested with plain Python objects. The DB layer (engine.py) fetches records, converts
them to ``Movement`` objects and calls these functions.
"""
from __future__ import annotations

from collections import Counter, defaultdict, deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from statistics import median
from typing import Iterable
from zoneinfo import ZoneInfo

RULE_VERSION = "TraceSense Core 1.0"
RISK_WINDOW = timedelta(hours=24)
RAPID_ONWARD_WINDOW = timedelta(minutes=30)
BREADTH_THRESHOLD = 5
REPORTING_TZ = ZoneInfo("Asia/Kolkata")


@dataclass(frozen=True)
class Movement:
    """One directed value movement, either a source-linked record or an internal ledger transfer."""
    key: str                    # unique edge key, e.g. "tx:42" or "tb:TB-..."
    ref: str                    # human reference shown to investigators
    sender: str
    receiver: str
    amount: Decimal
    at: datetime                # timezone-aware
    kind: str                   # "observed" | "ledger"
    status: str = "OBSERVED"    # OBSERVED | SUCCESS | FAILED
    provenance: dict = field(default_factory=dict, compare=False, hash=False)

    @property
    def moved_value(self) -> bool:
        """Failed ledger attempts never count as value movement."""
        return self.kind == "observed" or self.status == "SUCCESS"

    @property
    def evidence_state(self) -> str:
        if self.kind == "ledger":
            return "ledger_confirmed" if self.status == "SUCCESS" else "failed_attempt"
        return "observed_normalized" if self.provenance.get("provenance_status") == "normalized" else "observed"


# --------------------------------------------------------------------------------------
# Risk rules
# --------------------------------------------------------------------------------------

def evaluate_risk(recipient: str, movements: Iterable[Movement], as_of: datetime) -> dict:
    """Evaluate rules-v1 for ``recipient`` over the 24 hours ending at ``as_of``.

    Returns the level, human-readable reasons and an evidence bundle per reason listing the
    exact records that triggered it. Only movements that actually moved value are considered.
    """
    start = as_of - RISK_WINDOW
    window = [m for m in movements if m.moved_value and start <= m.at <= as_of]
    incoming = sorted((m for m in window if m.receiver == recipient), key=lambda m: m.at)
    outgoing = sorted((m for m in window if m.sender == recipient), key=lambda m: m.at)
    senders = {m.sender for m in incoming}
    receivers = {m.receiver for m in outgoing}

    reasons: list[str] = []
    evidence: list[dict] = []
    if len(senders) >= BREADTH_THRESHOLD:
        reasons.append(f"Observed incoming transfers from {len(senders)} distinct counterparties in the last 24 hours")
        evidence.append({"code": "INBOUND_BREADTH", "threshold": BREADTH_THRESHOLD, "observed": len(senders),
                         "counterparties": sorted(senders), "records": [m.ref for m in incoming]})
    if len(receivers) >= BREADTH_THRESHOLD:
        reasons.append(f"Observed outgoing transfers to {len(receivers)} distinct counterparties in the last 24 hours")
        evidence.append({"code": "OUTBOUND_BREADTH", "threshold": BREADTH_THRESHOLD, "observed": len(receivers),
                         "counterparties": sorted(receivers), "records": [m.ref for m in outgoing]})
    if incoming and outgoing:
        first_in = incoming[0]
        rapid = [m for m in outgoing if first_in.at <= m.at <= first_in.at + RAPID_ONWARD_WINDOW]
        if rapid:
            elapsed = (rapid[0].at - first_in.at).total_seconds() / 60
            reasons.append("Incoming and outgoing transfers overlap within a short observation window")
            evidence.append({"code": "RAPID_ONWARD", "window_minutes": int(RAPID_ONWARD_WINDOW.total_seconds() // 60),
                             "first_incoming": first_in.ref, "first_onward": rapid[0].ref,
                             "elapsed_minutes": round(elapsed, 1), "records": [first_in.ref] + [m.ref for m in rapid]})

    count = len(incoming) + len(outgoing)
    if len(reasons) >= 2:
        level = "review"
    elif reasons:
        level = "caution"
    elif count:
        level = "no_known_warning"
        reasons.append("No configured rule was triggered by the available observed records")
    else:
        level = "insufficient_information"
        reasons.append("No transaction records for this recipient were found in the available dataset")
    return {"level": level, "reasons": reasons, "evidence": evidence, "observed_count": count,
            "window_start": start, "window_end": as_of, "rule_version": RULE_VERSION}


# --------------------------------------------------------------------------------------
# Graph assembly
# --------------------------------------------------------------------------------------

def assemble_graph(root: str, movements: Iterable[Movement], *, max_hops: int, truncated: bool = False) -> dict:
    """Turn collected movements into a graph payload with flow levels and node statistics.

    ``level`` places each account on a left-to-right flow axis: the root is 0, accounts that
    received value from it are positive, accounts that sent value towards it are negative.
    ``hop`` is the undirected hop distance used for the traversal bound.
    """
    edges = sorted({m.key: m for m in movements}.values(), key=lambda m: (m.at, m.key))
    adjacency: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for m in edges:
        adjacency[m.sender].append((m.receiver, +1))
        adjacency[m.receiver].append((m.sender, -1))

    level = {root: 0}
    hop = {root: 0}
    queue = deque([root])
    while queue:
        node = queue.popleft()
        for neighbour, direction in adjacency.get(node, []):
            if neighbour not in hop:
                hop[neighbour] = hop[node] + 1
                level[neighbour] = level[node] + direction
                queue.append(neighbour)

    stats: dict[str, dict] = {n: {"in_total": Decimal("0"), "out_total": Decimal("0"), "in_count": 0, "out_count": 0,
                                  "senders": set(), "receivers": set(), "failed_attempts": 0} for n in hop}
    for m in edges:
        if not m.moved_value:
            stats[m.sender]["failed_attempts"] += 1
            continue
        stats[m.sender]["out_total"] += m.amount
        stats[m.sender]["out_count"] += 1
        stats[m.sender]["receivers"].add(m.receiver)
        stats[m.receiver]["in_total"] += m.amount
        stats[m.receiver]["in_count"] += 1
        stats[m.receiver]["senders"].add(m.sender)

    nodes = []
    for node_id in sorted(hop, key=lambda n: (hop[n], level[n], n)):
        s = stats[node_id]
        nodes.append({
            "id": node_id, "level": level[node_id], "hop": hop[node_id], "is_root": node_id == root,
            "in_total": str(s["in_total"]), "out_total": str(s["out_total"]),
            "in_count": s["in_count"], "out_count": s["out_count"],
            "unique_senders": len(s["senders"]), "unique_receivers": len(s["receivers"]),
            "observed_flow_difference": str(s["in_total"] - s["out_total"]),
            "failed_attempts": s["failed_attempts"],
            "at_traversal_boundary": hop[node_id] >= max_hops,
        })

    edge_rows = [{
        "key": m.key, "source": m.sender, "target": m.receiver, "transaction_ref": m.ref,
        "amount": str(m.amount), "timestamp": m.at.isoformat(), "edge_type": "observed_transaction" if m.kind == "observed" else (
            "ledger_transfer" if m.status == "SUCCESS" else "payment_attempt"),
        "status": m.status, "evidence_state": m.evidence_state, "flow_confirmed": m.moved_value, **m.provenance,
    } for m in edges]

    times = [m.at for m in edges]
    states = Counter(m.evidence_state for m in edges)
    return {
        "root": root, "nodes": nodes, "edges": edge_rows,
        "summary": {
            "node_count": len(nodes), "edge_count": len(edge_rows), "max_hops": max_hops,
            "first_timestamp": min(times).isoformat() if times else None,
            "last_timestamp": max(times).isoformat() if times else None,
            "evidence_states": dict(states), "truncated": truncated,
            "levels": {"min": min(level.values()), "max": max(level.values())},
        },
        "note": ("Bounded analytical neighbourhood built from persisted source records and internal ledger entries. "
                 "Only observed records and SUCCESS ledger transfers count as value movement; failed attempts are shown separately. "
                 "Accounts on the traversal boundary may have further unseen connections. "
                 "An observed-flow difference is not missing money: the account may hold a balance or use rails outside this dataset."),
    }


# --------------------------------------------------------------------------------------
# Account summary and time series
# --------------------------------------------------------------------------------------

def _day_key(stamp: datetime) -> str:
    return stamp.astimezone(REPORTING_TZ).date().isoformat()


def daily_series(movements: Iterable[Movement], *, end: datetime | None, days: int) -> list[dict]:
    """Daily count/volume for the ``days`` days ending at ``end`` (data-anchored, reporting timezone)."""
    moved = [m for m in movements if m.moved_value]
    if end is None:
        end = max((m.at for m in moved), default=datetime.now(timezone.utc))
    end_day = end.astimezone(REPORTING_TZ).date()
    buckets = {(end_day - timedelta(days=offset)).isoformat(): {"count": 0, "volume": Decimal("0"), "ledger": 0}
               for offset in range(days)}
    for m in moved:
        key = _day_key(m.at)
        if key in buckets:
            buckets[key]["count"] += 1
            buckets[key]["volume"] += m.amount
            if m.kind == "ledger":
                buckets[key]["ledger"] += 1
    return [{"date": day, "count": b["count"], "volume": str(b["volume"]), "ledger_count": b["ledger"]}
            for day, b in sorted(buckets.items())]


def max_burst(stamps: list[datetime], window: timedelta = timedelta(hours=1)) -> int:
    """Largest number of events inside any sliding window."""
    stamps = sorted(stamps)
    best, left = 0, 0
    for right, stamp in enumerate(stamps):
        while stamp - stamps[left] > window:
            left += 1
        best = max(best, right - left + 1)
    return best


def account_summary(ref: str, movements: Iterable[Movement]) -> dict:
    moved = [m for m in movements if m.moved_value and ref in (m.sender, m.receiver)]
    incoming = [m for m in moved if m.receiver == ref]
    outgoing = [m for m in moved if m.sender == ref]
    in_by = defaultdict(lambda: [0, Decimal("0")])
    out_by = defaultdict(lambda: [0, Decimal("0")])
    for m in incoming:
        in_by[m.sender][0] += 1; in_by[m.sender][1] += m.amount
    for m in outgoing:
        out_by[m.receiver][0] += 1; out_by[m.receiver][1] += m.amount

    def top(groups):
        ranked = sorted(groups.items(), key=lambda kv: (-kv[1][1], kv[0]))[:6]
        return [{"account": k, "count": c, "volume": str(v)} for k, (c, v) in ranked]

    stamps = [m.at for m in moved]
    last = max(stamps) if stamps else None
    onward = []
    for m in outgoing:
        prior = [i.at for i in incoming if i.at <= m.at]
        if prior:
            onward.append((m.at - max(prior)).total_seconds() / 60)
    in_total = sum((m.amount for m in incoming), Decimal("0"))
    out_total = sum((m.amount for m in outgoing), Decimal("0"))
    rules = evaluate_risk(ref, moved, last) if last else None
    return {
        "account": ref,
        "record_count": len(moved), "in_count": len(incoming), "out_count": len(outgoing),
        "in_total": str(in_total), "out_total": str(out_total),
        "observed_flow_difference": str(in_total - out_total),
        "unique_senders": len(in_by), "unique_receivers": len(out_by),
        "first_seen": min(stamps).isoformat() if stamps else None,
        "last_seen": last.isoformat() if last else None,
        "median_amount": str(median([m.amount for m in moved])) if moved else None,
        "max_events_in_one_hour": max_burst(stamps),
        "median_onward_minutes": round(median(onward), 1) if onward else None,
        "ledger_records": sum(1 for m in moved if m.kind == "ledger"),
        "top_senders": top(in_by), "top_receivers": top(out_by),
        "daily": daily_series(moved, end=last, days=30) if last else [],
        "rules_at_last_activity": rules,
        **behaviour_profile(ref, moved, incoming, outgoing, last, rules),
    }


AMOUNT_BUCKETS = [(Decimal("0"), Decimal("500"), "Under ₹500"), (Decimal("500"), Decimal("2000"), "₹500–2K"),
                  (Decimal("2000"), Decimal("10000"), "₹2K–10K"), (Decimal("10000"), Decimal("50000"), "₹10K–50K"),
                  (Decimal("50000"), None, "₹50K+")]


def behaviour_profile(ref: str, moved: list[Movement], incoming: list[Movement], outgoing: list[Movement],
                      last: datetime | None, rules: dict | None) -> dict:
    """Extra, explainable behaviour measures for the Account Analysis screen."""
    hourly = [{"hour": h, "in": 0, "out": 0} for h in range(24)]
    for m in moved:
        h = m.at.astimezone(REPORTING_TZ).hour
        hourly[h]["in" if m.receiver == ref else "out"] += 1
    buckets = []
    for lo, hi, label in AMOUNT_BUCKETS:
        buckets.append({"label": label, "in": sum(1 for m in incoming if m.amount >= lo and (hi is None or m.amount < hi)),
                        "out": sum(1 for m in outgoing if m.amount >= lo and (hi is None or m.amount < hi))})
    daily_split = []
    if last:
        end_day = last.astimezone(REPORTING_TZ).date()
        days = {(end_day - timedelta(days=o)).isoformat(): {"in": Decimal("0"), "out": Decimal("0"), "in_count": 0, "out_count": 0}
                for o in range(30)}
        for m in moved:
            key = _day_key(m.at)
            if key in days:
                side = "in" if m.receiver == ref else "out"
                days[key][side] += m.amount
                days[key][side + "_count"] += 1
        daily_split = [{"date": d, "in": str(v["in"]), "out": str(v["out"]), "in_count": v["in_count"], "out_count": v["out_count"]}
                       for d, v in sorted(days.items())]
    parties: dict[str, dict] = {}
    for m in moved:
        other = m.sender if m.receiver == ref else m.receiver
        p = parties.setdefault(other, {"account": other, "received_from_count": 0, "received_from": Decimal("0"),
                                       "sent_to_count": 0, "sent_to": Decimal("0"), "first": m.at, "last": m.at})
        if m.receiver == ref:
            p["received_from_count"] += 1; p["received_from"] += m.amount
        else:
            p["sent_to_count"] += 1; p["sent_to"] += m.amount
        p["first"] = min(p["first"], m.at); p["last"] = max(p["last"], m.at)
    counterparties = sorted(parties.values(), key=lambda p: -(p["received_from"] + p["sent_to"]))[:20]
    counterparties = [{**p, "received_from": str(p["received_from"]), "sent_to": str(p["sent_to"]),
                       "first": p["first"].isoformat(), "last": p["last"].isoformat(),
                       "both_ways": p["received_from_count"] > 0 and p["sent_to_count"] > 0} for p in counterparties]
    sources: dict[str, int] = {}
    for m in moved:
        key = "TraceBank ledger" if m.kind == "ledger" else (m.provenance.get("source_id") or "unknown source")
        sources[key] = sources.get(key, 0) + 1
    rule_table = []
    if rules:
        ev = {e["code"]: e for e in rules.get("evidence", [])}
        window = [m for m in moved if rules["window_start"] <= m.at <= rules["window_end"]]
        senders = len({m.sender for m in window if m.receiver == ref})
        receivers = len({m.receiver for m in window if m.sender == ref})
        rapid = ev.get("RAPID_ONWARD")
        rule_table = [
            {"rule": "Inbound breadth", "threshold": f"≥ {BREADTH_THRESHOLD} distinct senders in 24 h", "observed": f"{senders} senders",
             "triggered": "INBOUND_BREADTH" in ev},
            {"rule": "Outbound breadth", "threshold": f"≥ {BREADTH_THRESHOLD} distinct recipients in 24 h", "observed": f"{receivers} recipients",
             "triggered": "OUTBOUND_BREADTH" in ev},
            {"rule": "Rapid onward movement", "threshold": f"sent within {int(RAPID_ONWARD_WINDOW.total_seconds() // 60)} min of first receipt",
             "observed": f"{rapid['elapsed_minutes']} min" if rapid else "not observed", "triggered": rapid is not None},
        ]
    plain = _plain_summary(ref, incoming, outgoing, parties, rules)
    return {"hourly": hourly, "amount_buckets": buckets, "daily_split": daily_split, "counterparties": counterparties,
            "sources": sources, "rule_table": rule_table, "plain_summary": plain}


def _plain_summary(ref: str, incoming: list[Movement], outgoing: list[Movement], parties: dict, rules: dict | None) -> str:
    if not incoming and not outgoing:
        return f"No transfers involving {ref} are recorded."
    parts = [f"{ref} received {len(incoming)} transfer{'s' if len(incoming) != 1 else ''} from "
             f"{len({m.sender for m in incoming})} account(s) and sent {len(outgoing)} to {len({m.receiver for m in outgoing})}."]
    both = [p for p in parties.values() if p["received_from_count"] and p["sent_to_count"]]
    if both:
        parts.append(f"{len(both)} counterpart{'ies' if len(both) != 1 else 'y'} both sent to and received from this account.")
    if rules:
        names = {"INBOUND_BREADTH": "many distinct senders", "OUTBOUND_BREADTH": "many distinct recipients", "RAPID_ONWARD": "fast onward movement"}
        signals = [names[e["code"]] for e in rules.get("evidence", [])]
        level = rules["level"].replace("_", " ")
        parts.append(f"At its last activity, rules-v1 says {level}" + (f" because of {', '.join(signals)}." if signals else "."))
    return " ".join(parts)
