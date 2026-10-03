# Trace.Pay — QR identity, payment outcomes and observability update

## Implemented in this revision

- Server-authoritative, unique `@tracepay` pilot ID assigned at profile creation. Client-supplied IDs are ignored.
- Per-profile QR payload includes the assigned pilot ID, registered display name and profile ID. It is a Trace.Pay pilot QR, not a bank-issued UPI QR.
- QR scanner accepts `tracepay://pay` payloads; scanning opens the recipient flow and the API resolves the registered participant/merchant name before risk assessment.
- Recipient lookup endpoint: `GET /api/v1/pilot/recipients/{vpa_id}`.
- Animated QR scanner remains equipped with a moving scan beam, flashlight and success/error haptics.
- Amount typography increased; success and failure outcomes now have distinct animated states, status text, haptics and persisted transfer references.
- Milestone telemetry endpoint records profile/QR/recipient/risk/transfer events without keystrokes, passwords, OTPs, dates of birth or raw form contents.
- Live WebSocket notifications for profile creation, recipient resolution, risk assessments and pilot transfers; authenticated console can inspect audit events at `/api/v1/console/activity`.
- New System observability view in both the web console and iOS Profile shows FastAPI, PostgreSQL, Redis, NetworkX graph tracing, explainable risk rules and WebSocket status.
- CNN/deep-learning is displayed as a research extension that is not configured and does not make live decisions. The current active risk engine is rules-based; graph tracing uses NetworkX MultiDiGraph.
- PostgreSQL encrypted profile fields are widened to TEXT in the SQLAlchemy model and on API startup; a standalone SQL migration is also included.
- Preserves research framing: provenance-first evidence, explicit evidence gaps, and risk alerts as advisory leads rather than proof of fraud.

## Important limits

- This remains a closed-loop TraceBank test-value ledger. It does not connect to real bank accounts or UPI settlement rails.
- QR lookup verifies registration and shows the profile's registered name; a QR payload alone is not proof of identity or authority to receive real money.
- System health indicates service reachability, not that every feature is configured or production-ready.
- Client telemetry records workflow milestones only, not every tap or keystroke.
