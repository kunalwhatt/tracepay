# Trace.Pay 2.0.0 — Full Platform Redesign

> New version with a redesigned web console, separate iOS risk-review screen, iOS transfer history, native Android app, name-based `@tracepay` IDs and Azure deployment templates. Read `VERSION_2_0_0_RELEASE_NOTES.md` and `infra/azure/README.md` first. Cloud resources are not pre-provisioned; you must deploy and configure the placeholders.

# Trace.Pay Studio 3.0 — Green + Blue Experience Rebuild

This release applies the supplied Trace.Pay logo across the native iOS app and web console, strengthens the green/electric-blue design system, adds home-screen pull-to-refresh, and makes successful internal-ledger transfers visible in the temporal graph and live audit timeline.

## Studio 3.0 highlights
- Supplied wordmark and emblem installed in the web console and iOS asset catalog.
- Refined light-first green + blue UI, premium typography, responsive cards, hover motion, graph edge animation, and animated live status.
- iOS home pull-to-refresh and navigation/scanner milestone telemetry.
- Personal QR payload uses the server-assigned unique Trace.Pay ID and profile ID; recipient names are resolved from the authenticated backend instead of trusting a QR-embedded display name.
- Graph explorer combines source-linked observed records with internal-ledger transfers. Confirmed successful ledger movement is green; failed attempts are shown separately in red/dashed styling.
- Transfer, profile, merchant, funding, risk, recipient-resolution, ingestion and app milestone events feed the persistent activity log and WebSocket timeline.
- Explainable risk assessment includes successful internal-ledger transfer activity alongside source-linked transaction records.
- NetworkX, PostgreSQL, Redis, FastAPI, WebSockets and the CNN research extension remain visible in system observability. CNN is explicitly marked not configured unless an actual model is connected.

## Start locally
1. Copy `.env.example` to `.env` and set strong local secrets.
2. Run `docker compose up --build -d`.
3. Open the web console at `http://localhost:5173` and API docs at `http://localhost:8000/docs`.
4. Open `ios-app/TracePay.xcodeproj` in Xcode. For Simulator use `http://127.0.0.1:8000`; for a physical iPhone use your Mac's LAN IP in `TRACEPAY_API_BASE_URL`.

## Important payment boundary
The app has a consumer payment-app interaction model, unique account IDs and an internal double-entry ledger. It is not connected to a bank or NPCI/UPI payment rail. Do not represent internal-ledger results as external bank settlement. Google Sign-In and Sign in with Apple require provider credentials and server-side token verification before production use.

# Trace.Pay Live Foundation

A backend-connected foundation for the Trace.Pay iOS client and investigator web console. It deliberately contains **no seeded/demo transaction records**. Empty dashboards remain empty until authorised records are ingested.

## Included

- `backend/`: FastAPI REST API, PostgreSQL persistence, password hashing, short-lived JWT sessions, role checks, audit events, recipient risk rules, CSV ingestion, NetworkX transaction graph, payment handoff-intent tracking and authenticated live WebSocket updates.
- `web-console/`: React operations console with database-backed metrics, pilot participant and merchant directories, simulated pilot transfers, transaction search, ingestion jobs, recipient assessment, and graph/source inspection.
- `ios-app/`: native SwiftUI iOS application source and Xcode project. Includes login/register, glass-style interface, camera QR scanner for `upi://pay` payloads, manual UPI ID entry, API-backed recipient risk checks, transaction list and external UPI app handoff.
- `docker-compose.yml`: PostgreSQL, Redis, API and web console for local development.

## Important payment and regulatory boundary

This project is **not an RBI-regulated payment system** and is not approved by NPCI or any bank. It does not hold funds, collect a UPI PIN, or execute/settle a UPI payment itself.

The iOS client parses a standard `upi://pay` QR payload, asks the Trace.Pay API for a risk assessment, creates a `payment_intent` record, and then asks iOS to open a compatible payment app. The API records whether iOS accepted the app handoff. **That does not prove the user authorised or completed a payment.** The completion status and actual sender/receiver/amount must come from an authorised PSP/bank/provider integration or another permitted, reliable transaction source. A consumer iOS app cannot independently monitor all transactions occurring inside Google Pay, PhonePe or bank apps.

Do not describe a QR scan, app handoff, user screenshot or locally generated event as a completed bank transaction. The `transactions` table is populated only by authorised CSV ingestion in this foundation. A provider-specific webhook/SDK or approved feed must be designed and security-reviewed after the provider and its integration contract are known.

The current login is a development baseline: password hashing, short-lived JWTs, role separation and audit events are included, but email verification, MFA/passkeys, formal KYC, key management, formal security testing and regulatory/legal approvals are not. Self-registration creates a `pilot_user` account; operations roles must be provisioned separately. Configure the bootstrap administrator through environment variables. Do not expose this service to the public internet as-is.

## 1. Configure local environment

Requirements: Docker Desktop, Xcode 16+ (for iOS), and a recent Node/npm if running the web console outside Docker.

```bash
cp .env.example .env
```

Edit `.env` and set a long random `POSTGRES_PASSWORD` and `JWT_SECRET`. Set `BOOTSTRAP_ADMIN_EMAIL` and `BOOTSTRAP_ADMIN_PASSWORD` to provision the first operations account on startup. Keep the JWT/PII encryption secrets stable after profiles exist, and keep `.env` out of version control.

Start the backend, database and web console:

```bash
docker compose up --build
```

- API docs: http://localhost:8000/docs
- API health: http://localhost:8000/health
- Web console: http://localhost:5173

Sign in to the web console with the configured bootstrap administrator or another provisioned analyst/reviewer account. Pilot users register in the iOS app and cannot access the operations console.

## 2. Import approved transaction data

The CSV endpoint requires an authenticated analyst/admin token and a `source_id`. Required columns:

```csv
transaction_id,event_id,sender_id,receiver_id,amount,timestamp,source_record_ref
```

No data rows are bundled. `timestamp` must include a timezone, e.g. `2026-09-28T10:00:00+05:30`. Use pseudonymised identifiers unless the data custodian has specifically approved otherwise. Do not upload bank statements or personal identifiers without appropriate permission, minimisation and storage controls.

Example using a token obtained from `/api/v1/auth/login`:

```bash
curl -X POST 'http://localhost:8000/api/v1/ingestion/csv?source_id=approved-source-01' \
  -H 'Authorization: Bearer YOUR_ACCESS_TOKEN' \
  -F 'file=@authorised-transactions.csv'
```

The importer validates each row, records the ingestion job, enforces unique event IDs and source-record references, and reports accepted/rejected/duplicate counts. The dashboard, transaction table, graph and risk assessment use persisted records only.

## 3. Open the iOS app

Open `ios-app/TracePay.xcodeproj` in Xcode and select an iPhone simulator or device. In the target's `Info.plist`, set `TRACEPAY_API_BASE_URL`:

- iOS Simulator: `http://127.0.0.1:8000` normally reaches the Mac host.
- Physical iPhone: use the Mac's LAN IP for local testing, with both devices on the same network.
- Deployed environment: use a valid HTTPS API URL. Do not use plain HTTP for production.

For physical-device local testing, iOS App Transport Security may block cleartext HTTP. Prefer a local HTTPS development endpoint rather than weakening App Transport Security. Ensure the camera permission string is present; it is included in `Info.plist`.

The app registers/logs in against the API. Scan a UPI QR code containing a `upi://pay` URI, or enter a UPI ID. The recipient risk check queries records already ingested into this Trace.Pay instance. Continuing creates a handoff-intent record and opens a compatible payment app if iOS can resolve the UPI URL. It does not confirm the payment outcome.

## 4. API outline

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`
- `GET /api/v1/metrics`
- `GET /api/v1/transactions`
- `POST /api/v1/ingestion/csv`
- `GET /api/v1/ingestion/jobs`
- `POST /api/v1/risk/check`
- `GET /api/v1/graph/paths/{account_ref}`
- `POST /api/v1/payment-intents`
- `POST /api/v1/payment-intents/{intent_id}/handoff-result`
- `GET /api/v1/payment-intents`
- `WS /ws/live?token=SHORT_LIVED_JWT`

## 5. Production hardening before deployment

1. Add Alembic migrations instead of relying on `create_all` for schema evolution.
2. Add rate limiting, email verification, MFA/passkeys, password reset and session revocation.
3. Put the API behind HTTPS and a reverse proxy/WAF; restrict WebSocket origins and token exposure.
4. Use a secrets manager, managed database, encrypted backups, tested restore procedures and centralised security logs.
5. Define data-retention, access-review, correction/appeal and incident-response procedures.
6. Obtain supervisor, data-custodian, provider and legal review for datasets and payment integrations.
7. Select an authorised PSP/bank/provider and implement its documented transaction status/webhook mechanism with signature verification and idempotency. Do not guess provider callback formats.
8. Conduct privacy, threat-model, penetration, load and accessibility testing before any real users or sensitive data are onboarded.

## Status

This is an integrated development foundation, not a certified or production-approved financial product. The API and frontends are connected. Real QR parsing and payment-app handoff are implemented at the client level; actual payment settlement monitoring remains dependent on a provider integration. The backend creates its schema on startup for this development foundation; add formal migrations and production security controls before deployment.


## iOS UX update (September 2026)

The updated SwiftUI source removes the Activity/payment-history tab and any wallet/balance or bill/recharge surfaces. It adds an on-demand Contacts picker, exact-UPI-ID confirmation, Face ID and local 6-digit app MPIN unlock options, a branded Trace.Pay logo asset, scan haptics and an animated QR scan line, clearer risk-check loading/error states, and a payment-app selection sheet.

**Integration limitations:** UPI app URL schemes vary by app/version and must be tested on a physical device. iOS may only report that an app opened; this is not payment confirmation. Trace.Pay must not display a payment as successful or invent a UPI reference without an authorised provider callback/API. The local MPIN is an app-unlock convenience, not a bank/UPI PIN. The saved API token is stored in the iOS Keychain, but server-side token expiry/refresh still depends on the backend.

Open `ios-app/TracePay.xcodeproj` in Xcode and build for your iPhone. Review the API base URL in `TracePay/Info.plist` and set it to your Mac's LAN IP for physical-device testing. This source bundle has not been built in Xcode in this environment.

---

# Trace.Pay Pilot Revamp 2.0 — implementation notes

This revamp adds a light-first violet / electric-blue / lime interface, pilot participant profiles, merchant registry, an explicitly simulated transfer workflow, Redis-backed transfer rate limiting, and native iOS pilot-profile onboarding. Existing evidence-aware investigation endpoints remain in place.

## What is working in this build

- **Web operations console:** overview, pilot user directory, merchant registry, pilot simulation ledger, observed transactions, graph explorer, risk studio, and authorised CSV ingestion.
- **Pilot identity:** email/password account registration in the iOS app followed by a one-time profile form for display name, date of birth, pilot VPA, optional bank name and account last four digits. Profile and ledger consents are required.
- **Privacy defaults:** date of birth, name, bank name and account last-four are encrypted at rest using Fernet. The encryption key is derived from `PII_ENCRYPTION_KEY` when set, otherwise from `JWT_SECRET`. Keep the same secret across restarts and backups. The web directory intentionally does not return date of birth.
- **Merchant records:** administrators/analysts can add pilot merchant VPA identifiers and categories.
- **Pilot transfer records:** custom test records and batches of 10 random-value simulation records (₹50–₹1,500) are persisted with audit events and idempotency keys. Redis limits user-created simulations to 20 per minute.
- **Risk UI:** an animated assessment overlay, haptics, and reason-by-reason explanations. Results remain advisory and depend only on records ingested into this instance.
- **Redis:** used for API-side rate limiting; the `/api/v1/pilot/health` endpoint reports its status.

## Important boundary: this is not a real-money UPI provider

`SIMULATED_ONLY` / `pilot_simulation` records do not move funds, debit a bank account, credit a real recipient, or prove settlement. The existing UPI-app handoff only attempts to open a compatible installed app; opening an app is not proof of payment completion. Real payment execution, signed settlement callbacks, bank feeds, and reconciliation require a contracted and authorised bank/PSP/payment-provider integration, credentials, security review, and provider-specific testing. Do not label this pilot as a live UPI rail.

Google Sign-In and Sign in with Apple are not falsely simulated by this build. To enable them, configure OAuth / Apple developer identifiers, redirect URLs, bundle ID, associated domains/entitlements where required, and backend token verification. Live selfie/KYC verification similarly requires an approved verification provider; this build explicitly marks it as not connected and does not capture or store a selfie. Do not collect UPI PINs, OTPs, banking passwords, full account numbers, or identity documents in this prototype.

## Fresh local setup

1. Copy `.env.example` to `.env` and set strong, unique `POSTGRES_PASSWORD` and `JWT_SECRET` values. Set `BOOTSTRAP_ADMIN_EMAIL` and a strong `BOOTSTRAP_ADMIN_PASSWORD` (at least 12 characters) to provision the web-console administrator on first startup. Keep `.env` private.
2. Keep `PII_ENCRYPTION_KEY` stable once participant profiles exist. If omitted, the app derives the PII key from `JWT_SECRET`; changing that secret later makes existing encrypted profile fields unreadable.
3. From the project root run `docker compose up -d --build`.
4. Open `http://localhost:5173` for the web console and `http://localhost:8000/docs` for API docs.
5. Open `ios-app/TracePay.xcodeproj` in Xcode. For the simulator use `http://127.0.0.1:8000` as the API base URL. For a physical iPhone, configure `TRACEPAY_API_BASE_URL` to the Mac's LAN IP and ensure both devices are on the same trusted Wi-Fi network. Do not expose the API directly to the public internet without TLS, access controls, and a security review.

## Pilot endpoints

- `GET/POST /api/v1/pilot/profile` — read/create the signed-in user's one-time pilot profile.
- `GET /api/v1/pilot/users` — role-controlled participant directory; DOB is omitted.
- `GET/POST /api/v1/pilot/merchants` — list or create pilot merchant records.
- `GET /api/v1/pilot/transfers` — view simulated transfer records; participant accounts see their own records.
- `POST /api/v1/pilot/transfers` — create a simulation from the signed-in participant's profile.
- `POST /api/v1/pilot/admin/transfers` — create a custom simulation as an authorised analyst/admin.
- `POST /api/v1/pilot/admin/generate-transfers` — create a batch of random-amount simulation records for registered pilot participants and merchants.
- `GET /api/v1/pilot/health` — pilot mode and Redis status.

## Pilot readiness checklist before inviting real participants

- Complete a privacy impact assessment and provide a clear retention/deletion policy and participant notice.
- Review applicable Indian data-protection requirements with counsel; obtain documented consent and define a grievance/correction route.
- Use TLS, managed secrets, encrypted backups, least-privilege database access, log redaction, rate limits and an incident-response plan.
- Use synthetic or explicitly consented/pseudonymised test data; do not import real bank statements without permission and access controls.
- Configure Apple/Google authentication and a vetted identity-verification provider before representing those flows as live.
- Obtain formal PSP/bank integration and settlement callback access before attempting real payments.

## Build verification note

The Python source passes syntax compilation and the updated Swift files pass Swift parser checks. A complete Docker build and Xcode/iOS build were not run in this environment. Run `docker compose up -d --build` on your Mac and build the Xcode scheme there; report any build output before treating the app as release-ready.


# TraceBank closed-loop ledger update

This revision adds a functioning **internal TraceBank pilot ledger**. It is not a real bank, deposit account, or UPI rail. Pilot balances are test value only.

## Ledger behaviour

- Each pilot profile and merchant receives a zero-balance TraceBank wallet.
- Admin/analyst users can allocate pilot test value using the **TraceBank ledger** tab.
- A participant can transfer test value to another registered participant or merchant from the iOS risk-assessment flow using **Pay with TraceBank pilot**.
- The backend locks wallets in a stable order and posts debit and credit entries in one database transaction.
- `SUCCESS` means both internal postings committed. `FAILED` means no debit/credit posting occurred (for example, insufficient test balance). A repeated idempotency key returns the existing transfer rather than creating a duplicate.
- Wallet balances, transfer records, double-entry postings, and audit events persist in PostgreSQL. Redis rate limiting remains enabled.
- External UPI app handoff remains a separate option and never changes the TraceBank ledger status.

## Added endpoints

- `GET /api/v1/pilot/wallet` — signed-in user's TraceBank test balance.
- `GET /api/v1/pilot/ledger` — signed-in user's ledger postings.
- `GET /api/v1/pilot/admin/wallets` — operations wallet directory.
- `POST /api/v1/pilot/admin/fund` — allocate test value to a registered pilot user or merchant (admin/analyst only).
- `POST /api/v1/pilot/transfers` — execute an internal participant transfer.
- `POST /api/v1/pilot/admin/transfers` — execute a custom internal transfer (admin/analyst only).
- `POST /api/v1/pilot/admin/generate-transfers` — process a batch of internal test-value transfers; results can be `SUCCESS` or `FAILED` based on the sender's available test balance.

## Run after updating

```bash
docker compose up -d --build
```

Then open the web console at `http://localhost:5173` and API docs at `http://localhost:8000/docs`. Rebuild the iOS app in Xcode. This bundle has Python syntax validation, but a full Docker/Xcode build still needs to be run on the Mac.


## iOS app (Rebuild 2.1)

See `IOS_REBUILD_NOTES.md` for the redesigned SwiftUI app, setup steps, and social-auth integration limitations.


## QR identity and live system visibility (2026-09-29)

Pilot IDs are now assigned by the backend using the authenticated user identity and database uniqueness checks. The iOS app does not ask participants to invent a VPA. Each participant QR encodes their assigned Trace.Pay pilot ID and profile identifier; scanning it resolves the registered name from the API before the user can proceed to risk review. The QR is for the closed-loop TraceBank pilot only, not a bank-issued UPI QR.

The **System observability** page in the web console and **Profile → Research & live system** in iOS show current FastAPI/PostgreSQL/Redis reachability, the active NetworkX graph engine and explainable rules, the live event stream, and the CNN research extension marked as not configured. Key workflow events are persisted to the audit log and streamed to the console. This is milestone telemetry, not keystroke tracking.

The API startup safely widens encrypted profile fields to PostgreSQL `TEXT` so Fernet ciphertext is not truncated. The equivalent migration is recorded at `backend/migrations/20260929_widen_encrypted_profile_fields.sql`.
