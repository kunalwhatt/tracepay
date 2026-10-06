"""TraceSense and TraceScore.

TraceSense Core: the three original rules (inbound breadth, outbound breadth, rapid onward).
TraceSense Deep: behaviour and fraud signals: dwell / pass-through, temporal motifs, structuring,
round-trips, victim convergence, escalation, scam-typical amounts, mule lifecycle; plus network
signals computed over a neighbourhood: coordinated mules, k-core, bridges (betweenness), rings
(Louvain communities) and an explainable anomaly score (isolation forest).

TraceScore (0–100) adds points per signal, so every score lists exactly where it came from, how
confident it is, and the smallest change that would move it to another band. Advisory only.
"""
from __future__ import annotations

import math
import random
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from statistics import median
from typing import Iterable

from .analysis import BREADTH_THRESHOLD, RAPID_ONWARD_WINDOW, RISK_WINDOW, Movement, evaluate_risk

ENGINE = "TraceSense"
CORE_VERSION = "TraceSense Core 1.0"
SCORE_VERSION = "TraceScore 1.0"
BANDS = [(75, "high_review", "High review"), (50, "review", "Review"), (25, "watch", "Watch"), (0, "low", "Low")]
WEIGHTS = {  # expert-set starting weights; TraceBench reports how well they separate mules from others
    "INBOUND_BREADTH": 18, "OUTBOUND_BREADTH": 14, "RAPID_ONWARD": 16,
    "PASS_THROUGH": 14, "SHORT_DWELL": 8, "FAN_IN_OUT": 8, "STRUCTURING": 10, "ROUND_TRIP": 5,
    "VICTIM_CONVERGENCE": 12, "ESCALATION": 12, "SCAM_AMOUNTS": 6, "MULE_LIFECYCLE": 8,
    "COORDINATED": 8, "DENSE_CORE": 4, "BRIDGE": 5, "RING": 5, "ANOMALY": 6, "LARGE_RELAY": 12, "HIGH_FORWARDING": 25,
    "REGULAR_CUSTOMERS": -15,  # shop-like behaviour lowers the score (the tea-shop false positive)
}
LABELS = {
    "INBOUND_BREADTH": "Many distinct senders", "OUTBOUND_BREADTH": "Many distinct recipients", "RAPID_ONWARD": "Rapid onward movement",
    "PASS_THROUGH": "Money passes straight through", "SHORT_DWELL": "Money stays only minutes", "FAN_IN_OUT": "Collect-then-forward pattern",
    "STRUCTURING": "Structuring / smurfing amounts", "ROUND_TRIP": "Back-and-forth payments", "VICTIM_CONVERGENCE": "Mostly first-time payers",
    "ESCALATION": "Escalating payments from one payer", "SCAM_AMOUNTS": "Scam-typical amounts", "MULE_LIFECYCLE": "Mule-like account lifecycle",
    "COORDINATED": "Shares payers with other suspicious accounts", "DENSE_CORE": "In the dense core of a network", "BRIDGE": "Bridge between groups",
    "RING": "Part of a tightly linked ring", "ANOMALY": "Unusual compared with other accounts",
    "LARGE_RELAY": "Large amount relayed within minutes", "HIGH_FORWARDING": "Forwards nearly everything it receives", "REGULAR_CUSTOMERS": "Mostly returning customers (shop-like)",
}
SCAM_FEES = {Decimal(x) for x in ("499", "999", "1499", "1999", "2499", "4999", "9999")}
LIMITS = [Decimal(x) for x in ("10000", "25000", "50000", "100000", "200000")]
D0 = Decimal("0")


def band_for(score: int) -> tuple[str, str]:
    for floor, key, label in BANDS:
        if score >= floor:
            return key, label
    return "low", "Low"


def record_confidence(m: Movement) -> float:
    if m.kind == "ledger":
        return 1.0
    status = m.provenance.get("provenance_status")
    ref = str(m.provenance.get("source_record_ref") or "")
    if any(str(x).startswith(("name:", "unidentified:")) for x in (m.sender, m.receiver)):
        return 0.7
    return 0.85 if status == "normalized" else 1.0 if ref else 0.95


# --------------------------------------------------------------------------------------
# Account-level signals
# --------------------------------------------------------------------------------------

def dwell_profile(ref: str, moved: list[Movement]) -> dict:
    """FIFO lot matching inside one account: how long money stayed and how much left quickly."""
    lots: list[list] = []  # [arrived_at, amount]
    dwell: list[tuple[float, Decimal]] = []
    received = D0
    quick = D0
    for m in moved:
        if m.receiver == ref:
            lots.append([m.at, m.amount]); received += m.amount
        elif m.sender == ref:
            remaining = m.amount
            while remaining > 0 and lots:
                take = min(lots[0][1], remaining)
                minutes = (m.at - lots[0][0]).total_seconds() / 60
                dwell.append((minutes, take))
                if minutes <= 30:
                    quick += take
                lots[0][1] -= take; remaining -= take
                if lots[0][1] <= 0:
                    lots.pop(0)
    minutes = [d for d, _ in dwell]
    return {"median_dwell_minutes": round(median(minutes), 1) if minutes else None,
            "pass_through_30m": round(float(quick / received), 3) if received else 0.0,
            "forwarded_share": round(float(sum((a for _, a in dwell), D0) / received), 3) if received else 0.0}


def motifs(ref: str, moved: list[Movement], delta: timedelta = timedelta(minutes=30)) -> dict:
    ins = [m for m in moved if m.receiver == ref]
    outs = [m for m in moved if m.sender == ref]
    fan = []
    for o in outs:
        before = [i for i in ins if o.at - delta <= i.at <= o.at]
        if len({i.sender for i in before}) >= 3:
            fan.append({"out": o.ref, "ins": [i.ref for i in before]})
    relay = sum(1 for o in outs if any(o.at - delta <= i.at <= o.at for i in ins))
    burst = 0
    times = sorted(i.at for i in ins)
    for k, t in enumerate(times):
        burst = max(burst, sum(1 for u in times[k:] if u - t <= delta))
    return {"fan_in_out": fan[:5], "fan_in_out_count": len(fan), "relays": relay, "max_burst_30m": burst}


def structuring(ref: str, moved: list[Movement]) -> dict:
    ins = [m for m in moved if m.receiver == ref]
    hour = timedelta(hours=1)
    repeated = []
    by_amount: dict[Decimal, list[Movement]] = defaultdict(list)
    for m in ins:
        by_amount[m.amount].append(m)
    for amt, group in by_amount.items():
        group.sort(key=lambda m: m.at)
        for k in range(len(group)):
            window = [g for g in group[k:] if g.at - group[k].at <= hour]
            if len(window) >= 3:
                repeated.append({"amount": str(amt), "count": len(window), "records": [g.ref for g in window]})
                break
    ladders = []
    by_sender: dict[str, list[Movement]] = defaultdict(list)
    for m in ins:
        by_sender[m.sender].append(m)
    for sender, group in by_sender.items():
        group.sort(key=lambda m: m.at)
        run = [group[0]] if group else []
        for g in group[1:]:
            if g.amount < run[-1].amount and g.at - run[-1].at <= hour:
                run.append(g)
            else:
                if len(run) >= 3: ladders.append({"sender": sender, "amounts": [str(r.amount) for r in run]})
                run = [g]
        if len(run) >= 3: ladders.append({"sender": sender, "amounts": [str(r.amount) for r in run]})
    small = 0
    times = sorted(m.at for m in ins if m.amount < 1000)
    for k, t in enumerate(times):
        small = max(small, sum(1 for u in times[k:] if u - t <= timedelta(minutes=30)))
    under_limit = [m.ref for m in ins if any(l * Decimal("0.98") <= m.amount < l for l in LIMITS)]
    return {"repeated_amounts": repeated, "descending_ladders": ladders, "small_burst_30m": small, "just_under_limits": under_limit[:10]}


def round_trips(ref: str, moved: list[Movement], window: timedelta = timedelta(hours=24)) -> list[dict]:
    out = []
    partners = {m.receiver for m in moved if m.sender == ref} & {m.sender for m in moved if m.receiver == ref}
    for p in partners:
        to_p = [m for m in moved if m.sender == ref and m.receiver == p]
        from_p = [m for m in moved if m.sender == p and m.receiver == ref]
        if any(abs((a.at - b.at).total_seconds()) <= window.total_seconds() for a in to_p for b in from_p):
            out.append({"account": p, "sent": str(sum((m.amount for m in to_p), D0)), "received": str(sum((m.amount for m in from_p), D0)),
                        "transfers": len(to_p) + len(from_p)})
    return sorted(out, key=lambda r: -r["transfers"])


def victim_convergence(ref: str, moved: list[Movement], as_of: datetime) -> dict:
    ins = sorted((m for m in moved if m.receiver == ref), key=lambda m: m.at)
    seen: set[str] = set()
    first_time_window = []
    for m in ins:
        first = m.sender not in seen
        seen.add(m.sender)
        if first and as_of - RISK_WINDOW <= m.at <= as_of:
            first_time_window.append(m.sender)
    window_payers = {m.sender for m in ins if as_of - RISK_WINDOW <= m.at <= as_of}
    repeat = sum(1 for s, c in Counter(m.sender for m in ins).items() if c > 1)
    return {"payers_24h": len(window_payers), "first_time_payers_24h": len(first_time_window),
            "first_time_share": round(len(first_time_window) / len(window_payers), 3) if window_payers else 0.0,
            "repeat_payer_ratio": round(repeat / len(seen), 3) if seen else 0.0}


def escalation(ref: str, moved: list[Movement], window: timedelta = timedelta(days=7)) -> list[dict]:
    out = []
    by_sender: dict[str, list[Movement]] = defaultdict(list)
    for m in moved:
        if m.receiver == ref:
            by_sender[m.sender].append(m)
    for sender, group in by_sender.items():
        group.sort(key=lambda m: m.at)
        best: list[Movement] = []
        run: list[Movement] = []
        for g in group:
            if run and g.amount > run[-1].amount and g.at - run[0].at <= window:
                run.append(g)
            else:
                run = [g]
            if len(run) > len(best):
                best = list(run)
        if len(best) >= 3 and best[-1].amount >= best[0].amount * 3:
            out.append({"payer": sender, "amounts": [str(b.amount) for b in best], "growth": round(float(best[-1].amount / best[0].amount), 1)})
    return out


def lifecycle(ref: str, moved: list[Movement]) -> dict:
    stamps = sorted(m.at for m in moved)
    if not stamps:
        return {}
    ins = [m for m in moved if m.receiver == ref]
    days = max(1.0, (stamps[-1] - stamps[0]).total_seconds() / 86400)
    gaps = [(b - a).total_seconds() / 86400 for a, b in zip(stamps, stamps[1:])]
    dormant = None
    for k, g in enumerate(gaps):
        if g >= 14:
            after = [m for m in moved if m.at > stamps[k]]
            before = [m for m in moved if m.at <= stamps[k]]
            if sum((m.amount for m in after), D0) >= 5 * max(Decimal("1"), sum((m.amount for m in before), D0)):
                dormant = round(g, 1)
    in_volume = sum((m.amount for m in ins), D0)
    new_and_busy = days <= 7 and (in_volume >= 50000 or len(ins) >= 10)
    return {"active_days": round(days, 1), "dormant_gap_days": dormant, "new_and_busy": new_and_busy, "in_volume": str(in_volume)}


# --------------------------------------------------------------------------------------
# Network-level signals over a neighbourhood
# --------------------------------------------------------------------------------------

def k_core(adj: dict[str, set[str]]) -> dict[str, int]:
    degree = {n: len(v) for n, v in adj.items()}
    core = {}
    remaining = set(adj)
    k = 0
    while remaining:
        k = max(k, min(degree[n] for n in remaining))
        peel = [n for n in remaining if degree[n] <= k]
        while peel:
            n = peel.pop()
            if n not in remaining:
                continue
            remaining.discard(n); core[n] = k
            for m in adj[n]:
                if m in remaining:
                    degree[m] -= 1
                    if degree[m] <= k:
                        peel.append(m)
    return core


def betweenness(directed: dict[str, set[str]]) -> dict[str, float]:
    """Brandes' algorithm on the directed money graph (unweighted), normalised to 0..1."""
    nodes = set(directed) | {v for vs in directed.values() for v in vs}
    bc = dict.fromkeys(nodes, 0.0)
    for s in nodes:
        stack, pred = [], defaultdict(list)
        sigma = dict.fromkeys(nodes, 0.0); sigma[s] = 1.0
        dist = dict.fromkeys(nodes, -1); dist[s] = 0
        queue = [s]
        while queue:
            v = queue.pop(0); stack.append(v)
            for w in directed.get(v, ()):
                if dist[w] < 0:
                    dist[w] = dist[v] + 1; queue.append(w)
                if dist[w] == dist[v] + 1:
                    sigma[w] += sigma[v]; pred[w].append(v)
        delta = dict.fromkeys(nodes, 0.0)
        while stack:
            w = stack.pop()
            for v in pred[w]:
                delta[v] += sigma[v] / sigma[w] * (1 + delta[w])
            if w != s:
                bc[w] += delta[w]
    n = len(nodes)
    scale = 1 / ((n - 1) * (n - 2)) if n > 2 else 1.0
    return {k: round(v * scale, 4) for k, v in bc.items()}


def louvain(weights: dict[tuple[str, str], float], seed: int = 7) -> dict[str, int]:
    """One-level Louvain modularity optimisation (sufficient for neighbourhood-sized graphs)."""
    adj: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for (u, v), w in weights.items():
        if u == v:
            continue
        adj[u][v] += w; adj[v][u] += w
    nodes = list(adj)
    if not nodes:
        return {}
    m2 = sum(sum(n.values()) for n in adj.values())
    k = {n: sum(adj[n].values()) for n in nodes}
    comm = {n: i for i, n in enumerate(nodes)}
    tot = defaultdict(float)
    for n in nodes:
        tot[comm[n]] += k[n]
    rng = random.Random(seed)
    improved = True
    while improved:
        improved = False
        rng.shuffle(nodes)
        for n in nodes:
            c0 = comm[n]
            tot[c0] -= k[n]
            links = defaultdict(float)
            for m, w in adj[n].items():
                links[comm[m]] += w
            best, gain_best = c0, links.get(c0, 0) - tot[c0] * k[n] / m2
            for c, w in links.items():
                gain = w - tot[c] * k[n] / m2
                if gain > gain_best + 1e-12:
                    best, gain_best = c, gain
            comm[n] = best; tot[best] += k[n]
            if best != c0:
                improved = True
    relabel = {c: i for i, c in enumerate(sorted(set(comm.values())))}
    return {n: relabel[c] for n, c in comm.items()}


class _ITree:
    def __init__(self, data: list[list[float]], depth: int, limit: int, rng: random.Random):
        self.size = len(data)
        self.leaf = depth >= limit or len(data) <= 1
        if self.leaf:
            return
        dims = [d for d in range(len(data[0])) if max(r[d] for r in data) > min(r[d] for r in data)]
        if not dims:
            self.leaf = True; return
        self.dim = rng.choice(dims)
        lo, hi = min(r[self.dim] for r in data), max(r[self.dim] for r in data)
        self.split = rng.uniform(lo, hi)
        self.left = _ITree([r for r in data if r[self.dim] < self.split], depth + 1, limit, rng)
        self.right = _ITree([r for r in data if r[self.dim] >= self.split], depth + 1, limit, rng)

    def path(self, x: list[float], depth: int = 0) -> float:
        if self.leaf:
            return depth + _c(self.size)
        return (self.left if x[self.dim] < self.split else self.right).path(x, depth + 1)


def _c(n: int) -> float:
    return 0.0 if n <= 1 else 2 * (math.log(n - 1) + 0.5772156649) - 2 * (n - 1) / n


def isolation_scores(rows: dict[str, list[float]], trees: int = 80, sample: int = 128, seed: int = 11) -> dict[str, float]:
    """Isolation forest (Liu et al. 2008). Scores near 1 are anomalous, near 0.5 are ordinary."""
    keys = list(rows)
    if len(keys) < 8:
        return dict.fromkeys(keys, 0.5)
    rng = random.Random(seed)
    data = [rows[k] for k in keys]
    n = min(sample, len(data))
    limit = math.ceil(math.log2(n))
    forest = [_ITree(rng.sample(data, n), 0, limit, rng) for _ in range(trees)]
    cn = _c(n)
    return {k: round(2 ** (-(sum(t.path(rows[k]) for t in forest) / trees) / cn), 3) for k in keys}


FEATURES = ["distinct_senders_24h", "distinct_receivers_24h", "pass_through_30m", "median_dwell_min", "burst_30m",
            "first_time_share", "night_share", "round_trips"]


def account_features(ref: str, moved: list[Movement], as_of: datetime) -> list[float]:
    window = [m for m in moved if as_of - RISK_WINDOW <= m.at <= as_of and ref in (m.sender, m.receiver)]
    d = dwell_profile(ref, sorted((m for m in moved if ref in (m.sender, m.receiver)), key=lambda m: m.at))
    mo = motifs(ref, window)
    vc = victim_convergence(ref, moved, as_of)
    night = sum(1 for m in window if m.at.astimezone(timezone(timedelta(hours=5, minutes=30))).hour < 6)
    return [len({m.sender for m in window if m.receiver == ref}), len({m.receiver for m in window if m.sender == ref}),
            d["pass_through_30m"], min(1440.0, d["median_dwell_minutes"] if d["median_dwell_minutes"] is not None else 1440.0),
            mo["max_burst_30m"], vc["first_time_share"], night / len(window) if window else 0.0, len(round_trips(ref, window))]


def network_signals(movements: Iterable[Movement], as_of: datetime | None = None) -> dict[str, dict]:
    moved = sorted((m for m in movements if m.moved_value), key=lambda m: m.at)
    if not moved:
        return {}
    as_of = as_of or moved[-1].at
    undirected: dict[str, set[str]] = defaultdict(set)
    directed: dict[str, set[str]] = defaultdict(set)
    weights: dict[tuple[str, str], float] = defaultdict(float)
    senders_of: dict[str, set[str]] = defaultdict(set)
    for m in moved:
        undirected[m.sender].add(m.receiver); undirected[m.receiver].add(m.sender)
        directed[m.sender].add(m.receiver)
        weights[tuple(sorted((m.sender, m.receiver)))] += float(m.amount)
        senders_of[m.receiver].add(m.sender)
    cores = k_core(undirected)
    bc = betweenness(directed) if len(undirected) <= 400 else {}
    communities = louvain(weights)
    members: dict[int, list[str]] = defaultdict(list)
    for n, c in communities.items():
        members[c].append(n)
    coordinated: dict[str, list[dict]] = defaultdict(list)
    receivers = [r for r, s in senders_of.items() if len(s) >= 3]
    for i, a in enumerate(receivers):
        for b in receivers[i + 1:]:
            shared = senders_of[a] & senders_of[b]
            jac = len(shared) / len(senders_of[a] | senders_of[b])
            if len(shared) >= 3 and jac >= 0.5:
                coordinated[a].append({"account": b, "shared_payers": len(shared), "jaccard": round(jac, 2)})
                coordinated[b].append({"account": a, "shared_payers": len(shared), "jaccard": round(jac, 2)})
    rows = {n: account_features(n, moved, as_of) for n in undirected}
    iso = isolation_scores(rows)
    means = [sum(r[i] for r in rows.values()) / len(rows) for i in range(len(FEATURES))]
    stds = [max(1e-9, math.sqrt(sum((r[i] - means[i]) ** 2 for r in rows.values()) / len(rows))) for i in range(len(FEATURES))]
    bc_cut = sorted(bc.values())[int(len(bc) * 0.9)] if bc else 1.0
    out = {}
    for n in undirected:
        ring = members[communities[n]] if n in communities else []
        internal = sum(w for (u, v), w in weights.items() if u in ring and v in ring)
        touching = sum(w for (u, v), w in weights.items() if u in ring or v in ring)
        z = [(rows[n][i] - means[i]) / stds[i] for i in range(len(FEATURES))]
        top = sorted(range(len(FEATURES)), key=lambda i: -abs(z[i]))[:3]
        out[n] = {"core": cores.get(n, 0), "betweenness": bc.get(n, 0.0), "bridge": bc.get(n, 0) > 0 and bc.get(n, 0) >= bc_cut and bc.get(n, 0) >= 0.05,
                  "ring": {"id": communities.get(n), "size": len(ring), "internal_share": round(internal / touching, 2) if touching else 0.0,
                           "members": sorted(ring)[:12]},
                  "coordinated": coordinated.get(n, [])[:5],
                  "anomaly": {"score": iso.get(n, 0.5), "drivers": [{"feature": FEATURES[i], "value": round(rows[n][i], 3), "z": round(z[i], 2)} for i in top]}}
    return out


# --------------------------------------------------------------------------------------
# TraceScore
# --------------------------------------------------------------------------------------

def trace_score(ref: str, movements: Iterable[Movement], *, as_of: datetime | None = None, network: dict | None = None) -> dict:
    moved = sorted((m for m in movements if m.moved_value), key=lambda m: m.at)
    mine = [m for m in moved if ref in (m.sender, m.receiver)]
    if not mine:
        return {"account": ref, "score": None, "band": "insufficient_information", "band_label": "Insufficient information",
                "engine": ENGINE, "version": SCORE_VERSION, "contributions": [], "signals": {}, "confidence": 0.0,
                "counterfactuals": [], "core": evaluate_risk(ref, moved, as_of or datetime.now(timezone.utc))}
    as_of = as_of or mine[-1].at
    window = [m for m in mine if as_of - RISK_WINDOW <= m.at <= as_of]
    core = evaluate_risk(ref, moved, as_of)
    dw = dwell_profile(ref, mine)
    mo = motifs(ref, window)
    st = structuring(ref, window)
    rt = round_trips(ref, window)
    vc = victim_convergence(ref, mine, as_of)
    es = escalation(ref, mine)
    lc = lifecycle(ref, mine)
    scam = [m.ref for m in mine if m.receiver == ref and (m.amount in SCAM_FEES or (m.amount >= 100000 and m.amount % 100000 == 0))]
    net = (network or {}).get(ref, {})
    hits: list[tuple[str, str, list[str]]] = []
    for e in core["evidence"]:
        detail = f"{e['observed']} vs threshold {e['threshold']}" if "observed" in e else f"sent {e['elapsed_minutes']} min after first receipt"
        hits.append((e["code"], detail, e["records"]))
    received_24h = sum((m.amount for m in window if m.receiver == ref), D0)
    if dw["pass_through_30m"] >= 0.6 and received_24h >= 2000:
        hits.append(("PASS_THROUGH", f"{round(dw['pass_through_30m'] * 100)}% of received money left within 30 min", []))
    relays = [o for o in window if o.sender == ref and o.amount >= 10000
              and any(i.receiver == ref and o.at - timedelta(minutes=30) <= i.at <= o.at and o.amount >= i.amount * Decimal("0.45") for i in window)]
    # Delay-proof: waiting longer than 30 minutes does not hide an account that passes on almost everything.
    win_dw = dwell_profile(ref, window)
    if win_dw["forwarded_share"] >= 0.8 and received_24h >= 10000 and (win_dw["median_dwell_minutes"] or 0) <= 360:
        hits.append(("HIGH_FORWARDING", f"{round(win_dw['forwarded_share'] * 100)}% of ₹{received_24h} received was sent on (median stay {win_dw['median_dwell_minutes']} min)", []))
    if relays:
        hits.append(("LARGE_RELAY", f"₹{relays[0].amount} forwarded within 30 min of arriving", [r.ref for r in relays[:5]]))
    if dw["median_dwell_minutes"] is not None and dw["median_dwell_minutes"] <= 15:
        hits.append(("SHORT_DWELL", f"median stay {dw['median_dwell_minutes']} min", []))
    if mo["fan_in_out_count"]:
        hits.append(("FAN_IN_OUT", f"{mo['fan_in_out_count']} time(s): 3+ payers then an onward payment within 30 min", [x["out"] for x in mo["fan_in_out"]]))
    if st["repeated_amounts"] or st["descending_ladders"] or st["small_burst_30m"] >= 5 or st["just_under_limits"]:
        parts = []
        if st["repeated_amounts"]: parts.append(", ".join(f"₹{r['amount']}×{r['count']}" for r in st["repeated_amounts"][:3]))
        if st["descending_ladders"]: parts.append(f"{len(st['descending_ladders'])} shrinking ladder(s)")
        if st["small_burst_30m"] >= 5: parts.append(f"{st['small_burst_30m']} small payments in 30 min")
        if st["just_under_limits"]: parts.append(f"{len(st['just_under_limits'])} just under limits")
        hits.append(("STRUCTURING", "; ".join(parts), [r for x in st["repeated_amounts"] for r in x["records"]][:10]))
    if rt:
        hits.append(("ROUND_TRIP", ", ".join(r["account"] for r in rt[:3]), []))
    if vc["payers_24h"] >= 5 and vc["first_time_share"] >= 0.8:
        hits.append(("VICTIM_CONVERGENCE", f"{vc['first_time_payers_24h']} of {vc['payers_24h']} payers had never paid before", []))
    if es:
        hits.append(("ESCALATION", "; ".join(f"{e['payer']}: " + " → ".join('₹' + a for a in e['amounts']) for e in es[:2]), []))
    if scam:
        hits.append(("SCAM_AMOUNTS", f"{len(scam)} fee-like or round-lakh payment(s)", scam[:10]))
    if lc.get("dormant_gap_days") or lc.get("new_and_busy"):
        hits.append(("MULE_LIFECYCLE", "dormant then suddenly active" if lc.get("dormant_gap_days") else "new account already moving large value", []))
    if vc["repeat_payer_ratio"] >= 0.5 and len({m.sender for m in mine if m.receiver == ref}) >= 5:
        hits.append(("REGULAR_CUSTOMERS", f"{round(vc['repeat_payer_ratio'] * 100)}% of payers paid more than once", []))
    if net.get("coordinated"):
        hits.append(("COORDINATED", ", ".join(f"{c['account']} ({c['shared_payers']} shared payers)" for c in net["coordinated"][:2]), []))
    if net.get("core", 0) >= 3:
        hits.append(("DENSE_CORE", f"k-core {net['core']}", []))
    if net.get("bridge"):
        hits.append(("BRIDGE", f"betweenness {net['betweenness']}", []))
    ring = net.get("ring", {})
    if ring.get("size", 0) >= 3 and ring.get("internal_share", 0) >= 0.6 and len(hits) >= 2:
        hits.append(("RING", f"{ring['size']} accounts, {round(ring['internal_share'] * 100)}% of their money stays inside", []))
    if net.get("anomaly", {}).get("score", 0) >= 0.65:
        drivers = ", ".join(d["feature"].replace("_", " ") for d in net["anomaly"]["drivers"][:2])
        hits.append(("ANOMALY", f"isolation score {net['anomaly']['score']} (driven by {drivers})", []))
    contributions = [{"code": c, "label": LABELS[c], "points": WEIGHTS[c], "detail": d, "records": r,
                      "family": "core" if c in ("INBOUND_BREADTH", "OUTBOUND_BREADTH", "RAPID_ONWARD") else "deep"} for c, d, r in hits]
    contributions.sort(key=lambda x: -x["points"])
    score = max(0, min(100, sum(c["points"] for c in contributions)))
    band, label = band_for(score)
    confidence = round(sum(record_confidence(m) for m in mine) / len(mine) * min(1.0, 0.5 + len(mine) / 20), 2)
    return {"account": ref, "score": score, "band": band, "band_label": label, "engine": ENGINE, "version": SCORE_VERSION,
            "as_of": as_of.isoformat(), "contributions": contributions, "confidence": confidence,
            "counterfactuals": counterfactuals(score, contributions, core),
            "signals": {"dwell": dw, "motifs": mo, "structuring": st, "round_trips": rt, "victim_convergence": vc, "escalation": es,
                        "lifecycle": lc, "scam_amount_records": scam[:10], "network": net},
            "core": {"version": CORE_VERSION, "level": core["level"], "reasons": core["reasons"], "evidence": core["evidence"]}}


def counterfactuals(score: int, contributions: list[dict], core: dict) -> list[str]:
    """The smallest changes that would move the account to a different band."""
    out = []
    band = band_for(score)[0]
    running = score
    removed = []
    for c in (c for c in contributions if c["points"] > 0):  # largest contributions first
        running -= c["points"]; removed.append(c["label"].lower())
        if band_for(max(0, running))[0] != band:
            out.append(f"Without {' and '.join(removed)}, the score would be {max(0, running)} ({band_for(max(0, running))[1]}).")
            break
    for e in core.get("evidence", []):
        if e["code"] == "INBOUND_BREADTH":
            out.append(f"With {e['observed'] - BREADTH_THRESHOLD + 1} fewer distinct senders, the inbound-breadth signal would not fire.")
        if e["code"] == "RAPID_ONWARD":
            out.append(f"If the onward payment had waited {int(RAPID_ONWARD_WINDOW.total_seconds() // 60 - e['elapsed_minutes']) + 1} more minutes, the rapid-onward signal would not fire.")
    nxt = next((floor for floor, key, _ in reversed(BANDS) if floor > score), None)
    if nxt is not None:
        out.append(f"{nxt - score} more points would raise it to {band_for(nxt)[1]}.")
    return out[:4]
