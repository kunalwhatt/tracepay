# Trace.Pay — Azure setup (India pilot / production-ready path)

This document is the deployment plan for the rebuilt ingestion + real-time + Gemini backend.

## 1. Resource topology

Recommended region: `centralindia` if available for the required SKUs and acceptable for your users.

Create one resource group:

- `tracepay-rg`

Resources:

1. Azure Container Registry — `tracepayacr...`
2. Azure Container Apps Environment — `tracepay-env`
3. API Container App — `tracepay-api`
4. Web Container App — `tracepay-web`
5. Stream Worker Container App — `tracepay-stream-worker`
6. Azure Database for PostgreSQL Flexible Server — `tracepay-pg...`
7. Azure Managed Redis — `tracepay-redis...`
8. Azure Event Hubs Namespace — `tracepay-eh...`
9. Event Hub — `transactions`
10. Azure Storage Account — `tracepay...`
11. Blob containers — `tracepay-ingestion`, `tracepay-private`
12. Azure Key Vault — `tracepay-kv...`
13. Log Analytics / Container Apps environment logs
14. Optional Application Insights / Azure Monitor alerts

PostgreSQL is the durable source of truth. NetworkX is rebuilt from persisted records. Event Hubs is the realtime event transport. Redis is coordination/cache, not the transaction ledger.

## 2. Install Azure CLI on Mac

```bash
brew update
brew install azure-cli
az login
az account list -o table
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

## 3. Set shell variables

```bash
export AZ_SUBSCRIPTION_ID="YOUR_SUBSCRIPTION_ID"
export AZ_LOCATION="centralindia"
export AZ_RESOURCE_GROUP="tracepay-rg"
export ACR_NAME="tracepayacrYOURUNIQUE"
export PG_NAME="tracepay-pg-YOURUNIQUE"
export REDIS_NAME="tracepay-redis-YOURUNIQUE"
export KEYVAULT_NAME="tracepay-kv-YOURUNIQUE"
export EVENTHUB_NAMESPACE="tracepay-eh-YOURUNIQUE"
export EVENTHUB_NAME="transactions"
export STORAGE_NAME="tracepayYOURUNIQUE"
export PG_ADMIN_PASSWORD='USE-A-LONG-RANDOM-PASSWORD'
```

## 4. Create the foundation

```bash
cd infra/azure
./deploy-foundation.sh
```

The script creates the resource group, ACR, PostgreSQL, Managed Redis, Key Vault, Storage, Event Hubs and Container Apps environment.

For the first demo deployment PostgreSQL can use controlled public access. For a real production deployment, move PostgreSQL/Redis/Storage/Event Hubs behind private networking/private endpoints and restrict ingress/egress.

## 5. Create application secrets

Generate application secrets locally:

```bash
export JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
export PII_ENCRYPTION_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
```

Get a Gemini API key from Google AI Studio and keep it server-side. Never put it in the iOS, Android or browser bundle.

Store secrets in Key Vault:

```bash
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name jwt-secret --value "$JWT_SECRET"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name pii-encryption-key --value "$PII_ENCRYPTION_KEY"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name gemini-api-key --value "$GEMINI_API_KEY"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name postgres-admin-password --value "$PG_ADMIN_PASSWORD"
```

If Event Hubs is initially configured with an authorization-rule connection string, store it as a Key Vault secret too. Prefer managed identity/RBAC for Azure-to-Azure access where supported.

## 6. PostgreSQL connection string

The server is:

```text
<PG_NAME>.postgres.database.azure.com
```

Application connection string:

```text
postgresql+psycopg://tracepayadmin:<PASSWORD>@<PG_NAME>.postgres.database.azure.com:5432/tracepay?sslmode=require
```

Do not put the password into GitHub, `.env`, source code or a Docker image.

## 7. Redis

After the Managed Redis database exists, retrieve its endpoint/access information from the Azure portal or CLI. The application expects a TLS URI such as:

```text
rediss://:<ACCESS_KEY>@<REDIS_HOST>:10000/0
```

The exact hostname, port and authentication method should be copied from the Redis resource rather than guessed.

## 8. Event Hubs realtime pipeline

Create a send policy for the producer and a receive/consume policy for the worker, or use Entra/RBAC where appropriate.

Example namespace/event hub creation:

```bash
az eventhubs namespace create \
  --name "$EVENTHUB_NAMESPACE" \
  --resource-group "$AZ_RESOURCE_GROUP" \
  --location "$AZ_LOCATION" \
  --sku Standard

az eventhubs eventhub create \
  --name "$EVENTHUB_NAME" \
  --resource-group "$AZ_RESOURCE_GROUP" \
  --namespace-name "$EVENTHUB_NAMESPACE" \
  --partition-count 4 \
  --retention-time 24

az eventhubs eventhub consumer-group create \
  --resource-group "$AZ_RESOURCE_GROUP" \
  --namespace-name "$EVENTHUB_NAMESPACE" \
  --eventhub-name "$EVENTHUB_NAME" \
  --name tracepay-worker
```

The expected event JSON is:

```json
{
  "transaction_id": "TXN-10001",
  "event_id": "EVT-10001",
  "sender_id": "payer@tracepay",
  "receiver_id": "recipient@tracepay",
  "amount": "1250.00",
  "currency": "INR",
  "timestamp": "2026-10-03T10:00:00+05:30",
  "source_id": "upi-feed",
  "source_record_ref": "feed:10001"
}
```

Flow:

```text
Source / simulator
      |
      v
Azure Event Hubs
      |
      v
Trace.Pay stream-worker
      |
      +--> deterministic validation
      +--> PostgreSQL
      +--> graph rebuild / analytics
      +--> risk engine
      +--> WebSocket live console
```

## 9. Build images in ACR

From the project root:

```bash
az acr build --registry "$ACR_NAME" --image tracepay-api:latest ./backend
az acr build \
  --registry "$ACR_NAME" \
  --image tracepay-stream-worker:latest \
  --file backend/Dockerfile.worker ./backend
az acr build \
  --registry "$ACR_NAME" \
  --image tracepay-web:latest \
  --file web-console/Dockerfile \
  --build-arg VITE_API_BASE_URL="https://YOUR-API-FQDN" \
  ./web-console
```

Vite embeds `VITE_API_BASE_URL` at build time, so rebuild the web image whenever the API hostname changes.

## 10. Deploy Container Apps

Create the API first. Give it external HTTPS ingress and expose port 8000.

Environment values:

```text
DATABASE_URL=postgresql+psycopg://...
REDIS_URL=rediss://...
JWT_SECRET=<Key Vault secret reference>
PII_ENCRYPTION_KEY=<Key Vault secret reference>
GEMINI_API_KEY=<Key Vault secret reference>
GEMINI_ENABLED=true
GEMINI_MODEL=gemini-3.8-flash
CORS_ORIGINS=https://YOUR-WEB-FQDN
UPLOAD_MAX_MB=100
INGESTION_DEFAULT_TIMEZONE=Asia/Kolkata
EVENT_HUB_NAME=transactions
EVENT_HUB_CONSUMER_GROUP=tracepay-worker
```

Deploy the stream worker with the same database and Event Hubs configuration, but no external ingress.

Deploy the web container with HTTPS ingress and build it against the API FQDN.

## 11. Key Vault + Container Apps identity

For production, enable a managed identity on each Container App and give the identity `Key Vault Secrets User` on the Key Vault. Then reference Key Vault secrets from Container Apps rather than embedding secret values.

This is preferable to putting Gemini keys, database passwords or Redis keys into environment files.

## 12. Verify the cloud deployment

API:

```bash
curl https://YOUR-API-FQDN/health
```

Expected shape:

```json
{"status":"ok","service":"tracepay-api",...}
```

Web:

```text
https://YOUR-WEB-FQDN
```

Then:

1. Create an investigator account or bootstrap admin.
2. Sign in.
3. Open **Data Ingestion**.
4. Upload `data/samples/messy_transactions.xlsx`.
5. Confirm accepted/duplicate/rejected counts.
6. Open Dashboard.
7. Confirm transaction count and volume changed.
8. Open Transaction Search.
9. Open Graph Analysis and trace an account.
10. Run Risk Check.
11. Publish an Event Hub event with `scripts/publish_event.py`.
12. Confirm the transaction appears without waiting for a page refresh.

## 13. Gemini behavior

Gemini is intentionally not the financial-record validator.

The engine works in this order:

1. Read file.
2. Detect CSV delimiter / Excel sheets.
3. Normalize headers.
4. Apply deterministic alias mapping.
5. If required columns are still ambiguous and Gemini is enabled, ask Gemini only for a structured mapping suggestion.
6. Validate the suggested mapping against actual headers.
7. Normalize amount/timestamp/currency.
8. Generate IDs only when IDs are missing.
9. Reject rows that still lack required transaction facts.
10. Deduplicate against `(source_id, source_record_ref)` / transaction event identifiers.
11. Persist accepted records.
12. Update analytics/graph/risk and broadcast live events.

This prevents a generative model from silently inventing transaction data.
