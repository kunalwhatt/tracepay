# Trace.Pay — Azure ingestion + Gemini setup

## Pipeline

Browser / authorized file -> API preview/normalize -> PostgreSQL -> NetworkX -> risk engine -> WebSocket -> console

Realtime sources -> Azure Event Hubs -> `stream-worker` -> PostgreSQL -> graph/risk -> WebSocket -> console

Gemini is an **assistive mapper**, not the source of truth. Deterministic validation remains authoritative. Missing sender/receiver/amount/timestamp values are never fabricated.

## Supported uploads

- CSV / TXT with comma, semicolon, pipe or tab delimiters
- XLSX / XLSM
- XLS
- Common aliases for transaction ID, event ID, sender, receiver, amount, currency, timestamp and source record reference
- Currency symbols and comma-formatted amounts
- Multiple Excel sheets
- Missing transaction/event/source IDs are generated deterministically for the ingestion job
- Duplicate source records are counted rather than inserted
- Row-level errors are retained in the ingestion job

## Gemini

Set `GEMINI_API_KEY` only on the server. Never ship it in iOS, Android or browser code.

Recommended current stable model: `gemini-3.8-flash`.

Gemini is called only when deterministic column mapping cannot identify all required fields. It receives headers and a small sample for mapping suggestions. The backend validates every suggested mapping before use.

## Local

```bash
cp .env.example .env
# edit GEMINI_API_KEY, GEMINI_ENABLED, database secrets

docker compose build

docker compose up -d
curl http://localhost:8000/health
```

## Realtime HTTP event

Authenticated analyst/admin clients can POST a single transaction to:

`POST /api/v1/stream/transactions`

The API persists first and only then broadcasts a WebSocket event. `event_id` is idempotent.

## Azure Event Hubs

Set `EVENT_HUB_CONNECTION_STRING`, `EVENT_HUB_NAME` and `EVENT_HUB_CONSUMER_GROUP` on the worker. The worker consumes JSON events and persists them to PostgreSQL. Use Key Vault references for production secrets.
