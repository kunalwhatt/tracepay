from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from decimal import Decimal

from azure.eventhub import EventHubConsumerClient
from sqlalchemy import select

from app.db import SessionLocal
from app.models import Transaction
from app.ingestion_service import parse_timestamp

CONNECTION = os.getenv("EVENT_HUB_CONNECTION_STRING", "").strip()
EVENT_HUB_NAME = os.getenv("EVENT_HUB_NAME", "").strip()
CONSUMER_GROUP = os.getenv("EVENT_HUB_CONSUMER_GROUP", "$Default")


def handle_event(partition_context, event):
    if event is None or event.body is None:
        return
    try:
        payload = json.loads(event.body_as_str())
        required = ["sender_id", "receiver_id", "amount", "timestamp"]
        if any(not str(payload.get(k, "")).strip() for k in required):
            raise ValueError("Missing required stream fields")
        with SessionLocal() as db:
            # Sequence numbers are only unique within a partition, so fallbacks include the partition ID.
            position = f"{partition_context.partition_id}-{event.sequence_number}"
            transaction_ref = str(payload.get("transaction_id") or f"EVH-{position}")[:128]
            event_id = str(payload.get("event_id") or f"eventhub-{position}")[:128]
            existing = db.scalar(select(Transaction).where(Transaction.event_id == event_id))
            if existing:
                partition_context.update_checkpoint(event)
                return
            # Same parser as file ingestion: ISO first, day-first numeric dates, Asia/Kolkata default zone.
            timestamp = parse_timestamp(str(payload["timestamp"]))
            tx = Transaction(
                transaction_ref=transaction_ref,
                event_id=event_id,
                sender_id=str(payload["sender_id"]).strip()[:255],
                receiver_id=str(payload["receiver_id"]).strip()[:255],
                amount=Decimal(str(payload["amount"])),
                currency=str(payload.get("currency") or "INR").upper()[:3],
                occurred_at=timestamp.astimezone(timezone.utc),
                source_id=str(payload.get("source_id") or "azure-event-hubs")[:255],
                source_record_ref=str(payload.get("source_record_ref") or event_id)[:255],
                provenance_status="stream_observed",
            )
            db.add(tx)
            db.commit()
        partition_context.update_checkpoint(event)
    except Exception as exc:
        print(f"[stream] event failed: {type(exc).__name__}: {exc}", flush=True)


def main():
    if not CONNECTION or not EVENT_HUB_NAME:
        print("[stream] EVENT_HUB_CONNECTION_STRING/EVENT_HUB_NAME not configured; worker idle", flush=True)
        while True:
            time.sleep(60)
    client = EventHubConsumerClient.from_connection_string(
        conn_str=CONNECTION,
        consumer_group=CONSUMER_GROUP,
        eventhub_name=EVENT_HUB_NAME,
    )
    print(f"[stream] consuming Event Hub {EVENT_HUB_NAME} / {CONSUMER_GROUP}", flush=True)
    with client:
        client.receive(on_event=handle_event, starting_position="-1")


if __name__ == "__main__":
    main()
