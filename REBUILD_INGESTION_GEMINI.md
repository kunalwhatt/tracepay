# Trace.Pay ingestion + realtime rebuild

This release keeps the existing Trace.Pay modules and brand/UI direction while fixing the ingestion path and adding a real-time data foundation.

## Fixed ingestion

- CSV, TXT, XLS, XLSX and XLSM uploads
- multiple Excel sheets
- delimiter detection
- common transaction-column aliases
- currency/amount cleanup (`₹1,250`, `INR 1250`, `1,250.50`)
- timestamp parsing and India timezone default (`Asia/Kolkata`)
- generated event/transaction/source refs when safe
- duplicate handling
- row-level errors retained in ingestion jobs
- accepted/rejected/duplicate counts
- deterministic validation before persistence
- optional Gemini-assisted column mapping

## Gemini

Gemini is server-side only. It does not replace deterministic validation and it is not permitted to invent missing sender/receiver/amount/timestamp values.

Environment:

```text
GEMINI_ENABLED=true
GEMINI_MODEL=gemini-3.8-flash
GEMINI_API_KEY=...
```

## Realtime

- WebSocket `/ws/live`
- authenticated HTTP event endpoint `/api/v1/stream/transactions`
- optional Azure Event Hubs consumer worker (`backend/worker.py`)
- idempotent event IDs
- persist-first, broadcast-second behavior

## Analytics

`GET /api/v1/analytics/overview` provides persisted transaction count, total volume, currency breakdown and top senders/receivers. The console refreshes on WebSocket ingestion/transaction events and still polls as a recovery mechanism.

## Azure

See `infra/azure/AZURE_SETUP_TRACEPAY.md` and `infra/azure/README_INGESTION_GEMINI.md`.
