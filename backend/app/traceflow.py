"""TraceFlow: follow money correctly.

* Time-respecting (causal) reachability: a hop only counts if it happened after the money arrived.
* Attribution: how much of one traced payment sits in, or passed through, each account, by three
  standard methods (FIFO, LIFO, proportional). Disagreement between them is reported as uncertainty.
* Bottlenecks: node-capacitated max-flow / min-cut from the traced payment to where money rests.
* Hold list, cash-out exits, golden-hour countdown and peel chains.

Pure functions over ``analysis.Movement`` lists; no database access.
"""
from __future__ import annotations

import re
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Iterable

from .analysis import Movement

METHODS = ("fifo", "lifo", "proportional")
UNKNOWN = "unknown funds"
EXIT_PATTERNS = [
    ("cash withdrawal", re.compile(r"^cash:|\batm\b|withdraw", re.I)),
    ("crypto exchange", re.compile(r"wazirx|coindcx|binance|bitbns|zebpay|coinswitch|mudrex|okx|bybit|crypto", re.I)),
    ("gift card / voucher", re.compile(r"giftcard|gift\.card|voucher|amazonpay|flipkartgift|googleplay", re.I)),
    ("betting / gaming", re.compile(r"bet|casino|rummy|dream11|gaming", re.I)),
]
D0 = Decimal("0")


def exit_kind(account: str) -> str | None:
    for label, pattern in EXIT_PATTERNS:
        if pattern.search(account or ""):
            return label
    return None


def _moved(movements: Iterable[Movement]) -> list[Movement]:
    return sorted((m for m in movements if m.moved_value), key=lambda m: (m.at, m.key))


# --------------------------------------------------------------------------------------
# Time-respecting reachability
# --------------------------------------------------------------------------------------

def causal_reach(movements: Iterable[Movement], root: str, *, since: datetime | None = None, max_hops: int = 6) -> dict:
    """Forward: where could money that was at ``root`` (from ``since``) have gone, respecting time order.
    Backward: who could have funded ``root`` before its last outgoing transfer."""
    moved = _moved(movements)
    arrival: dict[str, tuple[datetime, int]] = {root: (since or datetime.min.replace(tzinfo=timezone.utc), 0)}
    forward_edges: set[str] = set()
    for m in moved:  # chronological sweep: each edge used only if it departs after money reached the sender
        if m.sender in arrival and m.at >= arrival[m.sender][0] and arrival[m.sender][1] < max_hops:
            forward_edges.add(m.key)
            hop = arrival[m.sender][1] + 1
            if m.receiver not in arrival or m.at < arrival[m.receiver][0]:
                arrival[m.receiver] = (m.at, hop)
    latest_out = max((m.at for m in moved if m.sender == root), default=datetime.max.replace(tzinfo=timezone.utc))
    departure: dict[str, tuple[datetime, int]] = {root: (latest_out, 0)}
    backward_edges: set[str] = set()
    for m in reversed(moved):
        if m.receiver in departure and m.at <= departure[m.receiver][0] and departure[m.receiver][1] < max_hops:
            backward_edges.add(m.key)
            hop = departure[m.receiver][1] + 1
            if m.sender not in departure or m.at > departure[m.sender][0]:
                departure[m.sender] = (m.at, hop)
    causal = forward_edges | backward_edges
    all_keys = {m.key for m in moved}
    return {"forward_edges": sorted(forward_edges), "backward_edges": sorted(backward_edges), "causal_edges": sorted(causal),
            "impossible_edges": sorted(all_keys - causal),
            "forward_accounts": sorted(set(arrival) - {root}), "backward_accounts": sorted(set(departure) - {root}),
            "naive_edge_count": len(all_keys), "causal_edge_count": len(causal),
            "removed_share": round(1 - len(causal) / len(all_keys), 3) if all_keys else 0.0}


# --------------------------------------------------------------------------------------
# Attribution (taint tracking)
# --------------------------------------------------------------------------------------

def _take(pool: list[list], amount: Decimal, method: str) -> dict[str, Decimal]:
    """Remove ``amount`` from an account's pool of [tag, amount] lots and return the composition taken."""
    taken: dict[str, Decimal] = defaultdict(lambda: D0)
    total = sum((lot[1] for lot in pool), D0)
    if method == "proportional" and total > 0:
        share = min(Decimal("1"), amount / total)
        for lot in pool:
            part = (lot[1] * share).quantize(Decimal("0.0001"))
            taken[lot[0]] += part
            lot[1] -= part
        remaining = amount - min(amount, total)
    else:
        remaining = amount
        order = range(len(pool)) if method == "fifo" else range(len(pool) - 1, -1, -1)
        for i in order:
            if remaining <= 0:
                break
            part = min(pool[i][1], remaining)
            taken[pool[i][0]] += part
            pool[i][1] -= part
            remaining -= part
    pool[:] = [lot for lot in pool if lot[1] > Decimal("0.00005")]
    if remaining > 0:
        taken[UNKNOWN] += remaining  # balance that existed before the data starts
    return dict(taken)


def attribute(movements: Iterable[Movement], seed_key: str, method: str = "fifo") -> dict:
    """Follow the money of one transfer (``seed_key``) through every later transfer."""
    moved = _moved(movements)
    seed = next((m for m in moved if m.key == seed_key), None)
    if seed is None:
        raise ValueError("seed transfer not found in the traced records")
    pools: dict[str, list[list]] = defaultdict(list)
    edge_flow: dict[str, Decimal] = {}
    received: dict[str, Decimal] = defaultdict(lambda: D0)
    first_arrival: dict[str, datetime] = {}
    for m in moved:  # one chronological pass; history before the seed only builds balances
        if m.key == seed_key:
            comp = {"seed": m.amount}
            if pools[m.sender]:
                _take(pools[m.sender], m.amount, method)
        else:
            comp = _take(pools[m.sender], m.amount, method)
        for tag, amt in comp.items():
            if amt > 0:
                pools[m.receiver].append([tag, amt])
        seed_part = comp.get("seed", D0)
        if seed_part > 0:
            edge_flow[m.key] = seed_part.quantize(Decimal("0.01"))
            received[m.receiver] += seed_part
            first_arrival.setdefault(m.receiver, m.at)
    holdings = {acct: sum((lot[1] for lot in pool if lot[0] == "seed"), D0).quantize(Decimal("0.01")) for acct, pool in pools.items()}
    holdings = {a: v for a, v in holdings.items() if v > 0}
    exits = {a: v for a, v in holdings.items() if exit_kind(a)}
    return {"method": method, "seed": {"key": seed.key, "ref": seed.ref, "from": seed.sender, "to": seed.receiver,
                                       "amount": str(seed.amount), "at": seed.at.isoformat()},
            "holdings": {a: str(v) for a, v in sorted(holdings.items(), key=lambda kv: -kv[1])},
            "edge_flow": {k: str(v) for k, v in edge_flow.items()},
            "exited": {a: str(v) for a, v in exits.items()},
            "reached": {a: {"amount": str(received[a].quantize(Decimal("0.01"))), "first_at": first_arrival[a].isoformat()} for a in received}}


def attribute_all(movements: Iterable[Movement], seed_key: str) -> dict:
    moved = list(movements)
    results = {method: attribute(moved, seed_key, method) for method in METHODS}
    seed_amount = Decimal(results["fifo"]["seed"]["amount"])
    accounts = set().union(*(set(r["holdings"]) for r in results.values()))
    def h(method, a): return Decimal(results[method]["holdings"].get(a, "0"))
    disagreement = {}
    for a, b in (("fifo", "lifo"), ("fifo", "proportional"), ("lifo", "proportional")):
        diff = sum((abs(h(a, x) - h(b, x)) for x in accounts), D0)
        disagreement[f"{a}_vs_{b}"] = float(round(diff / (2 * seed_amount), 3)) if seed_amount else 0.0
    table = [{"account": x, **{m: str(h(m, x)) for m in METHODS}, "exit": exit_kind(x)} for x in accounts]
    table.sort(key=lambda r: -max(Decimal(r[m]) for m in METHODS))
    return {"methods": results, "comparison": table, "disagreement": disagreement,
            "uncertainty_note": "Methods allocate pooled money differently. Wide disagreement means the data cannot say precisely whose money went where."}


# --------------------------------------------------------------------------------------
# Bottlenecks (node-capacitated max-flow / min-cut) and hold list
# --------------------------------------------------------------------------------------

def _max_flow(cap: dict[tuple[str, str], Decimal], source: str, sink: str) -> tuple[Decimal, set[str]]:
    graph: dict[str, set[str]] = defaultdict(set)
    flow: dict[tuple[str, str], Decimal] = defaultdict(lambda: D0)
    for (u, v) in cap:
        graph[u].add(v); graph[v].add(u)
    total = D0
    while True:
        parent = {source: None}
        queue = deque([source])
        while queue and sink not in parent:
            u = queue.popleft()
            for v in graph[u]:
                if v not in parent and cap.get((u, v), D0) - flow[(u, v)] > 0:
                    parent[v] = u; queue.append(v)
        if sink not in parent:
            return total, set(parent)  # reachable set defines the cut
        path, v = [], sink
        while parent[v] is not None:
            path.append((parent[v], v)); v = parent[v]
        push = min(cap.get(e, D0) - flow[e] for e in path)
        for u, v in path:
            flow[(u, v)] += push; flow[(v, u)] -= push
        total += push


def bottlenecks(movements: Iterable[Movement], attribution: dict) -> list[dict]:
    """Accounts whose hold would cut the most traced money off from where it now rests."""
    edge_flow = {k: Decimal(v) for k, v in attribution["edge_flow"].items()}
    holdings = {a: Decimal(v) for a, v in attribution["holdings"].items()}
    if not edge_flow:
        return []
    moved = {m.key: m for m in movements}
    seed_from = attribution["seed"]["from"]
    cap: dict[tuple[str, str], Decimal] = defaultdict(lambda: D0)
    nodes = set()
    for key, amt in edge_flow.items():
        m = moved.get(key)
        if not m:
            continue
        cap[(m.sender + "#out", m.receiver + "#in")] += amt
        nodes |= {m.sender, m.receiver}
    big = sum(edge_flow.values(), D0) * 10
    for n in nodes:  # node capacity = traced money that passed through it
        through = sum((amt for k, amt in edge_flow.items() if moved.get(k) and moved[k].receiver == n), D0)
        cap[(n + "#in", n + "#out")] = big if n == seed_from else max(through, Decimal("0.01"))
    cap[("SRC", seed_from + "#in")] = big
    for a, v in holdings.items():
        cap[(a + "#in", "SINK")] += v
    total, reachable = _max_flow(dict(cap), "SRC", "SINK")
    cut = []
    for n in nodes:
        if n == seed_from:
            continue
        if n + "#in" in reachable and n + "#out" not in reachable:
            cut.append({"account": n, "cuts": str(cap[(n + "#in", n + "#out")].quantize(Decimal("0.01")))})
    cut.sort(key=lambda r: -Decimal(r["cuts"]))
    return [{**c, "share": round(float(Decimal(c["cuts"]) / total), 3) if total else 0.0} for c in cut]


def hold_list(attribution: dict, cut: list[dict]) -> list[dict]:
    seed_amount = Decimal(attribution["seed"]["amount"])
    rows = []
    for acct, amount in attribution["holdings"].items():
        kind = exit_kind(acct)
        rows.append({"account": acct, "traced_funds_now": amount, "share": round(float(Decimal(amount) / seed_amount), 3),
                     "reason": f"Holds {'(already exited via ' + kind + ') ' if kind else ''}traced money now",
                     "exit": kind, "priority": 0})
    cut_accounts = {c["account"]: c for c in cut}
    for c in cut:
        if c["account"] not in attribution["holdings"]:
            rows.append({"account": c["account"], "traced_funds_now": "0", "share": c["share"], "exit": exit_kind(c["account"]),
                         "reason": "Bottleneck: most traced money passed through here", "priority": 0})
    rows = [r for r in rows if not r["exit"]] + [r for r in rows if r["exit"]]
    rows.sort(key=lambda r: (r["exit"] is not None, -Decimal(r["traced_funds_now"]), -(cut_accounts.get(r["account"], {}).get("share", 0))))
    for i, r in enumerate(rows, start=1):
        r["priority"] = i
        r["bottleneck"] = r["account"] in cut_accounts
    return rows


# --------------------------------------------------------------------------------------
# Golden hour and peel chains
# --------------------------------------------------------------------------------------

def golden_hour(attribution: dict, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    seed_at = datetime.fromisoformat(attribution["seed"]["at"])
    seed_amount = Decimal(attribution["seed"]["amount"])
    exited = sum((Decimal(v) for v in attribution["exited"].values()), D0)
    unknown_out = seed_amount - sum((Decimal(v) for v in attribution["holdings"].values()), D0)
    resting = seed_amount - exited - max(D0, unknown_out)
    reached = attribution["reached"]
    exit_times = [datetime.fromisoformat(v["first_at"]) for a, v in reached.items() if exit_kind(a)]
    elapsed = (now - seed_at).total_seconds() / 60
    return {"elapsed_minutes": round(elapsed, 1), "within_golden_hour": elapsed <= 60,
            "recoverable_amount": str(max(D0, resting).quantize(Decimal("0.01"))),
            "exited_amount": str(exited.quantize(Decimal("0.01"))),
            "recoverable_share": round(float(max(D0, resting) / seed_amount), 3) if seed_amount else 0.0,
            "minutes_to_first_exit": round((min(exit_times) - seed_at).total_seconds() / 60, 1) if exit_times else None,
            "hops_reached": len(reached)}


def peel_chains(movements: Iterable[Movement], *, window: timedelta = timedelta(hours=24), min_len: int = 3) -> list[dict]:
    """Chains where each hop forwards most, but not all, of what arrived (50–99%), in time order."""
    moved = _moved(movements)
    out_by: dict[str, list[Movement]] = defaultdict(list)
    for m in moved:
        out_by[m.sender].append(m)
    chains, seen = [], set()

    def extend(chain: list[Movement]):
        last = chain[-1]
        nxt = [n for n in out_by.get(last.receiver, []) if last.at < n.at <= last.at + window
               and Decimal("0.5") * last.amount <= n.amount < last.amount and n.receiver not in {c.sender for c in chain}]
        if not nxt:
            if len(chain) >= min_len:
                sig = tuple(c.key for c in chain)
                if sig not in seen and not any(set(sig) < set(s) for s in seen):
                    seen.add(sig)
                    chains.append(chain)
            return
        for n in nxt[:3]:
            extend(chain + [n])
    for m in moved:
        if len(chains) >= 50:
            break
        extend([m])
    out = []
    for c in chains:
        if any(set(x.key for x in c) < set(y["keys"]) for y in out):
            continue
        out.append({"accounts": [c[0].sender] + [x.receiver for x in c], "amounts": [str(x.amount) for x in c],
                    "keys": [x.key for x in c], "minutes": round((c[-1].at - c[0].at).total_seconds() / 60, 1),
                    "kept_share": round(float(1 - c[-1].amount / c[0].amount), 3)})
    return sorted(out, key=lambda r: -len(r["keys"]))[:20]
