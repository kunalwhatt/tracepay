# Trace.Pay 1.1 — Full Project Guide

Trace.Pay Studio contains a native SwiftUI iOS app, a React operations console, and a FastAPI/PostgreSQL backend for account onboarding, internal-ledger transfers, evidence-aware risk analysis, graph tracing, and live operational updates.

## Project layout

- `ios-app/TracePay.xcodeproj`: native iOS app (iOS 17+).
- `web-console/`: React + Vite operations console.
- `backend/`: FastAPI API, SQLAlchemy models, photo validation/storage, internal ledger, risk and graph endpoints.
- `docker-compose.yml`: PostgreSQL, Redis, API, and web console.
- `backend/migrations/`: SQL migrations and schema notes.
- 
## Start the stack

1. Install Docker Desktop and Xcode on macOS.
2. Copy `.env.example` to `.env` and set unique values for `POSTGRES_PASSWORD`, `JWT_SECRET`, and preferably `PII_ENCRYPTION_KEY`. Keep these values stable; they protect stored profile fields and photos.
3. Start services:

   ```bash
   docker compose up -d --build
   docker compose ps
   ```

4. Open `http://localhost:5173`, API docs at `http://localhost:8000/docs`, and health at `http://localhost:8000/health`.
5. Open `ios-app/TracePay.xcodeproj` in Xcode. For Simulator, `http://127.0.0.1:8000` can reach the Mac-hosted API. For a physical iPhone, set `TRACEPAY_API_BASE_URL` in `Info.plist` to your Mac's LAN IP or a deployed HTTPS API URL.

## Registration and account identity

1. Register using a unique email and a password with 12+ characters, at least one uppercase letter, one number, and one special character. The API enforces these rules.
2. Enter a full name without digits, date of birth confirming age 18+, and a gender option.
3. Capture a photo or choose one from the photo library. Apple Vision checks for exactly one face before the photo can be accepted. The API repeats image type, file signature, size, dimensions, and face-count checks.
4. The API assigns an opaque Trace.Pay ID and database customer/profile reference. The client cannot choose the account ID.

## Photo privacy and storage

- The API accepts JPEG, PNG, or WebP images up to 4 MB. The current iOS client normalizes selected images to JPEG before upload.
- Face detection checks the number of visible faces only. It is not face matching, liveness detection, KYC, or proof of identity.
- The backend encrypts photo bytes with the configured Fernet key before writing them to the private `tracepay_private_photos` Docker volume. Files are created with restrictive permissions; the storage key is not returned in profile JSON.
- `GET /api/v1/pilot/profile/photo` requires authentication and returns only the authenticated account's own photo with `Cache-Control: no-store`.
- Back up the database and photo volume securely. Keep `JWT_SECRET` / `PII_ENCRYPTION_KEY` stable or implement a planned key-rotation process.


## Web console and live data

- The console uses authenticated API requests and a live WebSocket for activity and transfer events, with periodic/visibility refresh as a fallback.
- Imported evidence records and internal-ledger transfers are shown as separate sources. Do not interpret a missing source record as proof that a transfer did not occur.
- Risk results are advisory review leads, not proof of fraud.

## Financial and deployment boundary

Trace.Pay's current payment flow records debits and credits inside its own internal ledger. External bank accounts, UPI settlement rails, and authoritative bank payment status are not integrated. A `SUCCESS` status refers to the internal ledger posting only. Do not collect UPI PINs, banking passwords, or OTPs. Do not present the application as a bank or as an actual UPI settlement service.

Before public deployment, complete a full Docker build, iOS build and device test, API integration tests, concurrency tests, privacy/security review, retention policy, and legal/regulatory review appropriate to the intended use.

## Validation status for this source bundle

- Python syntax compilation passed for backend `main.py`, `models.py`, and `schemas.py`.
- Password policy checks passed for five strong/weak examples.
- Swift syntax parsing passed for all Swift source files using `swiftc -frontend -parse`.
- JSX syntax parsing passed for the web console source.
- Docker Compose YAML parsing passed.
- A full Docker runtime build and full iOS SDK build were not available in the build environment and must be verified on the target Mac.
