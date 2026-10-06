"""Investigator assistant and evidence reports.

The built-in topics explain how Trace.Pay works and are always available. When Gemini is configured,
free-form questions are answered by Gemini using these topics plus live facts from the database.
Reports are assembled entirely from persisted records; an optional AI summary is clearly labelled.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import or_, select, desc
from sqlalchemy.orm import Session

from . import gemini_service
from .analysis import BREADTH_THRESHOLD, RAPID_ONWARD_WINDOW, RISK_WINDOW, RULE_VERSION
from .engine import graph_for_account, summarize_account, tx_movement
from .models import SourceConflict, Transaction

TOPICS: dict[str, dict[str, Any]] = {
    "hops": {
        "title": "What is a hop?",
        "body": ("A **hop** is one transfer step between two accounts. If A pays B, B is **1 hop** from A. If B then pays C, "
                 "C is **2 hops** from A.\n\nThe graph places the traced account in the middle. Accounts that sent money towards it "
                 "appear on the left (*hops before*), accounts that received money from it on the right (*hops after*).\n\n"
                 "The **hop limit** (1–4) bounds how far the trace goes in each direction. Accounts at the limit get a dashed amber "
                 "outline: they may have further transfers that were not loaded."),
        "table": {"title": "Example: a 3-hop trace from TP-A", "columns": ["Account", "Position", "Why"],
                  "rows": [["V1 (victim)", "1 hop before", "V1 paid TP-A"], ["TP-A", "Traced account", "Starting point"],
                           ["TP-B", "1 hop after", "TP-A paid TP-B"], ["TP-E", "2 hops after", "TP-B paid TP-E"],
                           ["ATM", "3 hops after", "TP-E withdrew cash"]]},
    },
    "risk": {
        "title": "How risk is flagged (TraceSense Core)",
        "body": (f"TraceSense Core looks only at the **{int(RISK_WINDOW.total_seconds() // 3600)} hours** before the check, and only at records "
                 "that actually moved value (source records and committed TraceBank transfers; failed attempts never count).\n\n"
                 "Three signals are checked. **Two or more** signals → **REVIEW**. **One** → **CAUTION**. None but some records → "
                 "**NO KNOWN WARNING**. No records → **INSUFFICIENT INFORMATION**.\n\n"
                 "Every signal stores the exact records that triggered it, so the result can be audited. The result is an "
                 "**advisory**, not proof of fraud: a busy shop can look like a collection account."),
        "table": {"title": "TraceSense Core signals", "columns": ["Signal", "Triggers when", "Why it matters"],
                  "rows": [["Inbound breadth", f"≥ {BREADTH_THRESHOLD} distinct senders in 24 h", "Many people paying one account (collection pattern)"],
                           ["Outbound breadth", f"≥ {BREADTH_THRESHOLD} distinct recipients in 24 h", "Money fanned out to many accounts (layering pattern)"],
                           ["Rapid onward movement", f"Money sent out within {int(RAPID_ONWARD_WINDOW.total_seconds() // 60)} min of the first receipt", "Funds passed through quickly instead of staying"]]},
    },
    "evidence": {
        "title": "What the line colours mean",
        "body": ("Every line in the graph is one persisted record. Its colour says what kind of evidence it is."),
        "table": {"title": "Evidence states", "columns": ["Colour", "Meaning", "Counts as value moved?"],
                  "rows": [["Violet", "Source record exactly as imported", "Yes"],
                           ["Light violet", "Source record where a value was interpreted (e.g. ambiguous date, derived counterparty)", "Yes"],
                           ["Green", "TraceBank internal transfer, both ledger sides committed", "Yes"],
                           ["Red dashed", "Failed TraceBank attempt", "No"]]},
    },
    "flow_difference": {
        "title": "Observed-flow difference",
        "body": ("Received minus sent, within the records Trace.Pay holds. A positive number means more came in than went out "
                 "**in this data**. It is **not missing money**: the account may hold a balance, or move money through banks, cash "
                 "or apps that are not in the dataset."),
    },
    "ingestion": {
        "title": "What happens when you import a file",
        "body": ("1. **Read**: every sheet is read; the real header row is found even below a statement preamble.\n"
                 "2. **Detect**: rules recognise common column names (sender, payee, withdrawal, narration, UTR ...).\n"
                 "3. **AI agent**: if columns are unclear, Gemini proposes which column is which. It never invents values, and "
                 "every suggestion is checked against the file.\n"
                 "4. **Review**: you can correct the mapping and the statement owner before importing.\n"
                 "5. **Validate**: each row is parsed (Indian DD/MM dates, ₹ amounts, Dr/Cr markers). Bad rows are rejected with a reason.\n"
                 "6. **Deduplicate**: rows already imported are skipped; rows that contradict an earlier source are kept as conflicts.\n"
                 "7. **Save**: accepted rows go to PostgreSQL with file, sheet and row provenance; the raw file is archived."),
    },
    "statements": {
        "title": "Bank and UPI statements",
        "body": ("A statement belongs to one account, so every row has the **statement owner** on one side. Money out "
                 "(withdrawal / Dr) becomes *owner → counterparty*; money in (deposit / Cr) becomes *counterparty → owner*.\n\n"
                 "The counterparty comes from a counterparty column, or from the narration: a UPI ID such as `ravi@okaxis`, a name "
                 "such as `UPI/123/RAVI KUMAR/...` (saved as `name:ravi.kumar`), ATM withdrawals (`cash:atm-withdrawal`), interest "
                 "or bank charges. Derived counterparties are marked *normalised* so you can check them against the source row."),
    },
    "conflicts": {
        "title": "Source conflicts",
        "body": ("If two files describe the same transaction reference differently (for example a different receiver), "
                 "Trace.Pay keeps the first record and stores the second as a **conflict**. Neither version is silently overwritten; "
                 "an investigator decides which source is right."),
    },
    "ledger": {
        "title": "Trace.Pay wallet ledger",
        "body": ("Payments made in the Trace.Pay apps are **internal Trace.Pay transfers**: both sides are posted in one database "
                 "transaction (double entry). They are not bank or UPI settlement. Failed attempts are recorded but never count as "
                 "money moved."),
    },
}
TOPIC_KEYWORDS = {
    "hops": ["hop", "hops", "level", "before", "after", "depth"],
    "risk": ["risk", "flag", "review", "caution", "rule", "rules", "assess", "score", "warning", "fraud"],
    "evidence": ["colour", "color", "line", "edge", "green", "violet", "red", "dashed", "evidence"],
    "flow_difference": ["difference", "missing", "balance", "flow"],
    "ingestion": ["import", "ingest", "upload", "file", "csv", "excel", "column", "mapping", "gemini", "ai"],
    "statements": ["statement", "narration", "withdrawal", "deposit", "counterparty", "bank"],
    "conflicts": ["conflict", "contradict", "duplicate"],
    "ledger": ["tracebank", "ledger", "payment", "wallet", "transfer"],
}


def knowledge_text() -> str:
    parts = []
    for topic in TOPICS.values():
        parts.append(f"## {topic['title']}\n{topic['body']}")
        if topic.get("table"):
            t = topic["table"]
            parts.append(t["title"] + ": " + "; ".join(" | ".join(r) for r in t["rows"]))
    return "\n\n".join(parts)


def match_topic(question: str) -> str:
    q = question.lower()
    scores = {k: sum(1 for w in words if w in q) for k, words in TOPIC_KEYWORDS.items()}
    best = max(scores, key=scores.get)
    return best if scores[best] else "risk"


def account_facts(db: Session, account_ref: str) -> dict[str, Any]:
    summary = summarize_account(db, account_ref)
    graph = graph_for_account(db, account_ref, max_hops=2, limit=200)
    rules = summary.get("rules_at_last_activity") or {}
    return {
        "account": account_ref,
        "received_total": summary.get("in_total"), "sent_total": summary.get("out_total"),
        "received_count": summary.get("in_count"), "sent_count": summary.get("out_count"),
        "unique_senders": summary.get("unique_senders"), "unique_receivers": summary.get("unique_receivers"),
        "first_seen": summary.get("first_seen"), "last_seen": summary.get("last_seen"),
        "busiest_hour_count": summary.get("max_events_in_one_hour"), "median_onward_minutes": summary.get("median_onward_minutes"),
        "rules_level_at_last_activity": rules.get("level"), "rules_reasons": rules.get("reasons"), "rules_evidence": rules.get("evidence"),
        "latest_stored_assessment": summary.get("latest_assessment"),
        "graph_2_hops": {"accounts": graph["summary"]["node_count"], "transfers": graph["summary"]["edge_count"],
                         "evidence_states": graph["summary"]["evidence_states"]},
        "top_senders": summary.get("top_senders", [])[:5], "top_receivers": summary.get("top_receivers", [])[:5],
    }


def ask(db: Session, question: str, account_ref: str | None, screen: str | None) -> dict[str, Any]:
    facts: dict[str, Any] = {"screen": screen, "rule_version": RULE_VERSION}
    if account_ref:
        try:
            facts["account_facts"] = account_facts(db, account_ref)
        except Exception as exc:  # noqa: BLE001
            facts["account_error"] = str(exc)[:200]
    topic_key = match_topic(question)
    if gemini_service.enabled():
        result = gemini_service.answer(question, knowledge_text(), facts)
        if result.get("ok"):
            return {"source": "gemini", "model": result["model"], "answer": result["answer"], "table": result["table"],
                    "follow_ups": result["follow_ups"], "topic": topic_key}
        fallback_note = f"The AI could not answer ({result.get('error', 'unknown error')[:160]}). Showing the built-in explanation."
    else:
        fallback_note = "AI answers need a Claude or Gemini key. Showing the built-in explanation."
    topic = TOPICS[topic_key]
    table = topic.get("table")
    if account_ref and facts.get("account_facts"):
        af = facts["account_facts"]
        table = {"title": f"Live facts for {account_ref}", "columns": ["Measure", "Value"],
                 "rows": [["Received", f"₹{af['received_total']} in {af['received_count']} transfers"],
                          ["Sent", f"₹{af['sent_total']} in {af['sent_count']} transfers"],
                          ["Distinct senders / recipients", f"{af['unique_senders']} / {af['unique_receivers']}"],
                          ["TraceSense Core at last activity", str(af.get("rules_level_at_last_activity") or "—")],
                          ["Accounts within 2 hops", str(af["graph_2_hops"]["accounts"])]]}
    return {"source": "built-in", "answer": f"_{fallback_note}_\n\n### {topic['title']}\n{topic['body']}", "table": table,
            "follow_ups": [TOPICS[k]["title"] for k in TOPICS if k != topic_key][:3], "topic": topic_key}


# --------------------------------------------------------------------------------------
# Evidence reports
# --------------------------------------------------------------------------------------

def build_report(db: Session, account_ref: str, *, hops: int = 2, include_ai_summary: bool = False) -> dict[str, Any]:
    summary = summarize_account(db, account_ref)
    graph = graph_for_account(db, account_ref, max_hops=hops, limit=600)
    rules = summary.get("rules_at_last_activity") or {}
    txs = db.scalars(select(Transaction).where(or_(Transaction.sender_id == account_ref, Transaction.receiver_id == account_ref))
                     .order_by(desc(Transaction.occurred_at)).limit(300)).all()
    rows = []
    for tx in txs:
        m = tx_movement(tx)
        rows.append({"time": tx.occurred_at.isoformat(), "from": tx.sender_id, "to": tx.receiver_id, "amount": str(tx.amount),
                     "reference": tx.transaction_ref, "evidence": m.evidence_state, "source": tx.source_id,
                     "file": tx.source_file, "sheet": tx.source_sheet, "row": tx.source_row})
    ledger = [e for e in graph["edges"] if e["edge_type"] != "observed_transaction" and account_ref in (e["source"], e["target"])]
    conflicts = db.scalars(select(SourceConflict).join(Transaction, SourceConflict.existing_transaction_id == Transaction.id)
                           .where(or_(Transaction.sender_id == account_ref, Transaction.receiver_id == account_ref))).all()
    sources: dict[str, int] = {}
    for r in rows:
        sources[r["source"] or "unknown"] = sources.get(r["source"] or "unknown", 0) + 1
    body = {
        "kind": "account_evidence", "version": 1, "generated_at": datetime.now(timezone.utc).isoformat(),
        "account": account_ref, "rule_version": RULE_VERSION,
        "summary": {k: summary.get(k) for k in ("record_count", "in_count", "out_count", "in_total", "out_total",
                                                 "observed_flow_difference", "unique_senders", "unique_receivers", "first_seen",
                                                 "last_seen", "median_amount", "max_events_in_one_hour", "median_onward_minutes")},
        "rules": {"level": rules.get("level"), "reasons": rules.get("reasons"), "evidence": rules.get("evidence"),
                  "window_end": rules.get("window_end"), "latest_stored": summary.get("latest_assessment")},
        "network": {"hops": hops, "accounts": graph["summary"]["node_count"], "transfers": graph["summary"]["edge_count"],
                    "evidence_states": graph["summary"]["evidence_states"], "truncated": graph["summary"]["truncated"],
                    "top_senders": summary.get("top_senders"), "top_receivers": summary.get("top_receivers")},
        "transactions": rows,
        "ledger_transfers": [{"time": e["timestamp"], "from": e["source"], "to": e["target"], "amount": e["amount"],
                              "reference": e["transaction_ref"], "status": e["status"]} for e in ledger][:200],
        "conflicts": [{"reference": c.transaction_ref, "fields": c.differing_fields, "incoming": json.loads(c.incoming_json),
                       "status": c.status} for c in conflicts],
        "sources": sources,
        "limitations": [
            "Built only from records persisted in Trace.Pay; transfers outside these datasets are not visible.",
            "TraceSense Core results are advisories based on simple patterns, not findings of fraud.",
            "Trace.Pay wallet transfers are internal ledger postings, not bank or UPI settlement.",
            "Normalised records contain interpreted values (e.g. derived counterparties or ambiguous dates); check the source row.",
        ],
    }
    if include_ai_summary:
        ai = gemini_service.summarize_report({k: body[k] for k in ("account", "summary", "rules", "network", "sources")})
        body["ai_summary"] = ({"text": ai["summary"], "model": ai["model"], "label": "AI-generated summary. Verify against the evidence below."}
                              if ai.get("ok") else {"error": ai.get("error")})
    return body
