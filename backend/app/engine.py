"""Database access for risk, graph and account analysis.

All rule and graph logic lives in ``analysis.py``; this module only fetches persisted records,
converts them into ``Movement`` objects and persists assessment results.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json

from sqlalchemy import or_, select, desc
from sqlalchemy.orm import Session

from .analysis import (Movement, RULE_VERSION, RISK_WINDOW, account_summary, assemble_graph,
                       daily_series, evaluate_risk)
from .models import PilotTransfer, RiskAssessment, Transaction

MAX_FRONTIER = 300


def tx_movement(tx: Transaction) -> Movement:
    return Movement(
        key=f"tx:{tx.id}", ref=tx.transaction_ref, sender=tx.sender_id, receiver=tx.receiver_id,
        amount=tx.amount, at=tx.occurred_at, kind="observed", status="OBSERVED",
        provenance={
            "source_id": tx.source_id, "source_record_ref": tx.source_record_ref,
            "provenance_status": tx.provenance_status, "event_id": tx.event_id,
            "ingestion_job_id": getattr(tx, "ingestion_job_id", None), "source_file": getattr(tx, "source_file", None),
            "source_sheet": getattr(tx, "source_sheet", None), "source_row": getattr(tx, "source_row", None),
            "ingested_at": tx.ingested_at.isoformat() if tx.ingested_at else None,
        })


def ledger_movement(t: PilotTransfer) -> Movement:
    status = (t.status or "UNKNOWN").upper()
    return Movement(
        key=f"tb:{t.transfer_ref}", ref=t.transfer_ref, sender=t.sender_vpa, receiver=t.receiver_vpa,
        amount=t.amount, at=t.created_at, kind="ledger", status=status,
        provenance={
            "source_id": "tracepay_internal_ledger", "source_record_ref": t.transfer_ref,
            "provenance_status": "ledger_confirmed" if status == "SUCCESS" else "attempt_failed",
            "failure_reason": getattr(t, "failure_reason", "") or None,
        })


def _movements_for(db: Session, refs: set[str], *, start: datetime | None = None, end: datetime | None = None,
                   limit: int = 5000, include_failed: bool = True) -> list[Movement]:
    tx_q = select(Transaction).where(or_(Transaction.sender_id.in_(refs), Transaction.receiver_id.in_(refs)))
    tb_q = select(PilotTransfer).where(or_(PilotTransfer.sender_vpa.in_(refs), PilotTransfer.receiver_vpa.in_(refs)))
    if start is not None:
        tx_q = tx_q.where(Transaction.occurred_at >= start); tb_q = tb_q.where(PilotTransfer.created_at >= start)
    if end is not None:
        tx_q = tx_q.where(Transaction.occurred_at <= end); tb_q = tb_q.where(PilotTransfer.created_at <= end)
    if not include_failed:
        tb_q = tb_q.where(PilotTransfer.status == "SUCCESS")
    rows = [tx_movement(t) for t in db.scalars(tx_q.order_by(desc(Transaction.occurred_at)).limit(limit))]
    rows += [ledger_movement(t) for t in db.scalars(tb_q.order_by(desc(PilotTransfer.created_at)).limit(limit))]
    return rows


def latest_data_timestamp(db: Session) -> datetime | None:
    from sqlalchemy import func
    candidates = [db.scalar(select(func.max(Transaction.occurred_at))),
                  db.scalar(select(func.max(PilotTransfer.created_at)).where(PilotTransfer.status == "SUCCESS"))]
    candidates = [c for c in candidates if c is not None]
    return max(candidates) if candidates else None


def assess_recipient(db: Session, recipient_ref: str, as_of: datetime | None = None) -> RiskAssessment:
    """Rules operate only on records actually persisted in this database.

    ``as_of`` defaults to now (live payment flow). Investigators and evaluation fixtures can pass a
    historical time so the 24-hour window covers the period the dataset actually describes.
    """
    as_of = (as_of or datetime.now(timezone.utc))
    if as_of.tzinfo is None:
        as_of = as_of.replace(tzinfo=timezone.utc)
    movements = _movements_for(db, {recipient_ref}, start=as_of - RISK_WINDOW, end=as_of, include_failed=False)
    result = evaluate_risk(recipient_ref, movements, as_of)
    row = RiskAssessment(recipient_ref=recipient_ref, level=result["level"], reasons_json=json.dumps(result["reasons"]),
                         evidence_json=json.dumps(result["evidence"]), transaction_count=result["observed_count"],
                         rule_version=RULE_VERSION, window_start=result["window_start"], window_end=result["window_end"])
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def collect_neighbourhood(db: Session, account_ref: str, max_hops: int = 3, limit: int = 500,
                          start: datetime | None = None, end: datetime | None = None) -> tuple[list[Movement], bool]:
    """Root-anchored bounded traversal: each hop queries only records touching the current frontier."""
    collected: dict[str, Movement] = {}
    seen = {account_ref}
    frontier = {account_ref}
    truncated = False
    for _ in range(max_hops):
        if not frontier:
            break
        if len(frontier) > MAX_FRONTIER:
            frontier = set(sorted(frontier)[:MAX_FRONTIER]); truncated = True
        remaining = limit - len(collected)
        if remaining <= 0:
            truncated = True; break
        batch = _movements_for(db, frontier, start=start, end=end, limit=remaining)
        next_frontier: set[str] = set()
        for m in batch:
            if m.key in collected:
                continue
            if len(collected) >= limit:
                truncated = True; break
            collected[m.key] = m
            for node in (m.sender, m.receiver):
                if node not in seen:
                    next_frontier.add(node)
        seen |= next_frontier
        frontier = next_frontier
    return list(collected.values()), truncated


def graph_for_account(db: Session, account_ref: str, max_hops: int = 3, limit: int = 500,
                      start: datetime | None = None, end: datetime | None = None) -> dict:
    movements, truncated = collect_neighbourhood(db, account_ref, max_hops, limit, start, end)
    return assemble_graph(account_ref, movements, max_hops=max_hops, truncated=truncated)


def recent_movements(db: Session, limit: int = 6000) -> list[Movement]:
    rows = [tx_movement(t) for t in db.scalars(select(Transaction).order_by(desc(Transaction.occurred_at)).limit(limit))]
    rows += [ledger_movement(t) for t in db.scalars(select(PilotTransfer).order_by(desc(PilotTransfer.created_at)).limit(limit))]
    return rows


def summarize_account(db: Session, account_ref: str) -> dict:
    summary = account_summary(account_ref, _movements_for(db, {account_ref}, include_failed=False))
    latest = db.scalar(select(RiskAssessment).where(RiskAssessment.recipient_ref == account_ref)
                       .order_by(desc(RiskAssessment.assessed_at)).limit(1))
    summary["latest_assessment"] = None if not latest else {
        "assessment_id": latest.id, "level": latest.level, "rule_version": latest.rule_version,
        "assessed_at": latest.assessed_at.isoformat(), "reasons": json.loads(latest.reasons_json)}
    return summary


def network_timeseries(db: Session, days: int = 14) -> dict:
    end = latest_data_timestamp(db)
    if end is None:
        return {"as_of": None, "days": []}
    start = end - (RISK_WINDOW * days) - RISK_WINDOW
    movements = [tx_movement(t) for t in db.scalars(select(Transaction).where(Transaction.occurred_at >= start))]
    movements += [ledger_movement(t) for t in db.scalars(select(PilotTransfer).where(
        PilotTransfer.created_at >= start, PilotTransfer.status == "SUCCESS"))]
    return {"as_of": end.isoformat(), "days": daily_series(movements, end=end, days=days)}
