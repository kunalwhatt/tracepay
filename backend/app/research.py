"""Trace.Pay research lab.

adversary(seed)          - how TraceScore holds up when mules adapt (slower, split, deeper layering, all combined)
learned_baseline(seeds)  - logistic model learned from TraceBench worlds vs TraceScore's expert weights
psi(a, b)                - population stability index between two score distributions (drift)
cold_start_factors(vpa)  - weak signals for UPI IDs with no history
dataset_csv(seed)        - a labelled TraceBench world as CSV (for temporal GNN experiments)
"""
from __future__ import annotations

import csv
import io
import math
import re

import numpy as np

from . import tracebench, tracesense

MULE_ROLES = getattr(tracebench, "MULE_ROLES", {"collector", "layer", "cashout", "mule"})

STRATEGIES = {
    "Baseline": {},
    "Slow mules (forward after 90 min)": {"mule_delay_min": 90},
    "Heavy splitting (5 parts)": {"split": 5},
    "Deeper layering (4 layers)": {"layers": 4},
    "All tactics combined": {"mule_delay_min": 90, "split": 5, "layers": 4},
}


def _world_scores(world: dict) -> tuple[list[str], dict, dict]:
    moves, roles = world["movements"], world["roles"]
    accounts = [a for a in roles if any(a in (m.sender, m.receiver) for m in moves)]
    network = tracesense.network_signals(moves)
    scores, codes = {}, {}
    for a in accounts:
        last = max(m.at for m in moves if a in (m.sender, m.receiver))
        ts = tracesense.trace_score(a, moves, as_of=last, network=network)
        scores[a] = ts["score"] or 0
        codes[a] = {c["code"] for c in ts.get("contributions", [])}
    return accounts, scores, codes


def _prf(pred: dict, roles: dict) -> dict:
    tp = sum(1 for a, p in pred.items() if p and roles[a] in MULE_ROLES)
    fp = sum(1 for a, p in pred.items() if p and roles[a] not in MULE_ROLES)
    fn = sum(1 for a, p in pred.items() if not p and roles[a] in MULE_ROLES)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"precision": round(precision, 3), "recall": round(recall, 3), "f1": round(f1, 3), "false_positives": fp, "mules": tp + fn}


def adversary(seed: int = 42) -> list[dict]:
    out = []
    for name, params in STRATEGIES.items():
        world = tracebench.generate_world(seed=seed, **params)
        accounts, scores, _ = _world_scores(world)
        roles = world["roles"]
        out.append({"strategy": name, "params": params, **_prf({a: scores[a] >= 25 for a in accounts}, roles),
                    "mule_avg_score": round(float(np.mean([scores[a] for a in accounts if roles[a] in MULE_ROLES] or [0])), 1),
                    "normal_avg_score": round(float(np.mean([scores[a] for a in accounts if roles[a] not in MULE_ROLES] or [0])), 1)})
    return out


def learned_baseline(train_seeds=(1, 2, 3), test_seed: int = 42, epochs: int = 600, lr: float = 0.3) -> dict:
    """Logistic regression on which TraceSense signals fired, trained on some worlds and tested on another."""
    signal_codes = list(tracesense.WEIGHTS)
    def featurize(seed):
        world = tracebench.generate_world(seed=seed)
        accounts, scores, codes = _world_scores(world)
        X = np.array([[1.0 if c in codes[a] else 0.0 for c in signal_codes] for a in accounts], dtype=np.float64)
        y = np.array([1.0 if world["roles"][a] in MULE_ROLES else 0.0 for a in accounts])
        return X, y, accounts, scores, world["roles"]
    parts = [featurize(s) for s in train_seeds]
    X = np.vstack([p[0] for p in parts]); y = np.concatenate([p[1] for p in parts])
    w = np.zeros(X.shape[1]); b = 0.0
    for _ in range(epochs):
        z = X @ w + b; p = 1 / (1 + np.exp(-z))
        g = p - y
        w -= lr * (X.T @ g / len(y) + 0.01 * w); b -= lr * g.mean()
    Xt, yt, acc, scores, roles = featurize(test_seed)
    pt = 1 / (1 + np.exp(-(Xt @ w + b)))
    learned = _prf({a: bool(pt[i] >= 0.5) for i, a in enumerate(acc)}, roles)
    expert = _prf({a: scores[a] >= 25 for a in acc}, roles)
    weights = sorted([{"code": c, "label": tracesense.LABELS.get(c, c), "expert_points": tracesense.WEIGHTS[c], "learned_weight": round(float(w[i]), 3)}
                      for i, c in enumerate(signal_codes)], key=lambda r: -r["learned_weight"])
    return {"train_seeds": list(train_seeds), "test_seed": test_seed, "expert_TraceScore": expert, "learned_model": learned, "signal_weights": weights}


def psi(expected: list[float], actual: list[float], bins=(0, 25, 50, 75, 101)) -> float:
    """Population stability index: <0.1 stable, 0.1–0.25 moderate drift, >0.25 significant drift."""
    def dist(xs):
        h, _ = np.histogram(xs, bins=bins)
        h = h.astype(float) + 0.5
        return h / h.sum()
    if not expected or not actual:
        return 0.0
    e, a = dist(expected), dist(actual)
    return round(float(np.sum((a - e) * np.log(a / e))), 4)


def cold_start_factors(vpa: str) -> list[dict]:
    """Weak hints for a UPI ID trace.pay has never seen (each only nudges the score)."""
    handle = vpa.split("@", 1)[0].lower()
    out = []
    digits = sum(ch.isdigit() for ch in handle)
    is_mobile = bool(re.fullmatch(r"[6-9]\d{9}", handle))
    if len(handle) >= 10 and not is_mobile and digits / len(handle) > 0.6:
        out.append({"code": "RANDOM_HANDLE", "label": "Random-looking UPI handle", "family": "cold_start", "points": 5,
                    "detail": "Mostly random digits, common for throwaway accounts."})
    if re.search(r"[bcdfghjklmnpqrstvwxz]{5,}", handle):
        out.append({"code": "GIBBERISH_HANDLE", "label": "Unpronounceable handle", "family": "cold_start", "points": 5,
                    "detail": "Long strings of consonants are typical of auto-generated accounts."})
    if re.search(r"(?:refund|support|helpdesk|kyc|reward|cashback|lottery|customer ?care|official)", handle):
        out.append({"code": "BAIT_HANDLE", "label": "Handle imitates support or rewards", "family": "cold_start", "points": 15,
                    "detail": "Names like 'refund', 'kyc' or 'customercare' are used to look official."})
    return out


def dataset_csv(seed: int = 42) -> str:
    world = tracebench.generate_world(seed=seed)
    buf = io.StringIO(); wr = csv.writer(buf)
    wr.writerow(["edge_id", "timestamp", "sender", "receiver", "amount", "sender_role", "receiver_role", "sender_is_mule", "receiver_is_mule"])
    roles = world["roles"]
    for m in sorted(world["movements"], key=lambda x: x.at):
        rs, rr = roles.get(m.sender, "unknown"), roles.get(m.receiver, "unknown")
        wr.writerow([m.key, m.at.isoformat(), m.sender, m.receiver, str(m.amount), rs, rr, int(rs in MULE_ROLES), int(rr in MULE_ROLES)])
    return buf.getvalue()
