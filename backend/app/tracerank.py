"""TraceRank: suspicion spreads from confirmed fraud through money flows.

Personalised PageRank with restart on seed accounts (confirmed fraud labels and complaint
recipients). Edges are weighted by amount. Accounts an investigator marked "not suspicious" stop
propagating (their share returns to the seeds), so feedback directly shapes the ranking. Each ranked
account gets an explaining path: the strongest money route from a seed.
"""
from __future__ import annotations

import heapq
import math
from collections import defaultdict
from typing import Iterable

from .analysis import Movement

DAMPING = 0.85


def trace_rank(movements: Iterable[Movement], seeds: dict[str, float], cleared: set[str] | None = None,
               iterations: int = 60, limit: int = 50) -> dict:
    cleared = cleared or set()
    weight: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for m in movements:
        if not m.moved_value:
            continue
        w = float(m.amount)
        weight[m.sender][m.receiver] += w      # downstream: where suspicious money went
        weight[m.receiver][m.sender] += w * 0.5  # upstream, weaker: who fed a suspicious account
    nodes = set(weight) | {v for n in weight.values() for v in n} | set(seeds)
    if not seeds or not nodes:
        return {"ranking": [], "seeds": sorted(seeds), "note": "Add a confirmed fraud label or a complaint to start TraceRank."}
    total_seed = sum(seeds.values())
    restart = {n: seeds.get(n, 0.0) / total_seed for n in nodes}
    rank = dict(restart)
    out_sum = {n: sum(weight[n].values()) for n in nodes}
    for _ in range(iterations):
        nxt = {n: (1 - DAMPING) * restart[n] for n in nodes}
        leaked = 0.0
        for n in nodes:
            r = rank[n]
            if n in cleared or out_sum[n] == 0:
                leaked += DAMPING * r
                continue
            for v, w in weight[n].items():
                nxt[v] += DAMPING * r * w / out_sum[n]
        for n in nodes:
            nxt[n] += leaked * restart[n]
        rank = nxt
    top = max((v for k, v in rank.items() if k not in seeds), default=0.0) or 1.0
    ranking = []
    for n, r in sorted(rank.items(), key=lambda kv: -kv[1]):
        if n in seeds or n in cleared or r <= 0:
            continue
        ranking.append({"account": n, "rank": round(r / top, 3), "raw": r, "path": explain_path(weight, seeds, n)})
        if len(ranking) >= limit:
            break
    return {"ranking": ranking, "seeds": sorted(seeds), "cleared": sorted(cleared)}


def explain_path(weight: dict[str, dict[str, float]], seeds: dict[str, float], target: str, max_hops: int = 6) -> list[str]:
    """Strongest route from any seed: Dijkstra on -log(share of the sender's money)."""
    dist, prev, heap = {}, {}, []
    for s in seeds:
        dist[s] = 0.0; heapq.heappush(heap, (0.0, 0, s))
    while heap:
        d, hops, n = heapq.heappop(heap)
        if n == target:
            break
        if d > dist.get(n, math.inf) or hops >= max_hops:
            continue
        total = sum(weight[n].values()) or 1.0
        for v, w in weight[n].items():
            nd = d - math.log(max(w / total, 1e-9))
            if nd < dist.get(v, math.inf):
                dist[v] = nd; prev[v] = n; heapq.heappush(heap, (nd, hops + 1, v))
    if target not in dist:
        return []
    path = [target]
    while path[-1] in prev:
        path.append(prev[path[-1]])
    return list(reversed(path))
