# Trace.Pay 2.0.0 — Full platform redesign

## Product redesign
- Premium light-first operations workspace with refreshed typography, spacing, surfaces, tables, dashboard cards, responsive layout and graph presentation.
- Native iOS payment review is now a dedicated risk-review page after recipient lookup and risk assessment.
- Payment authorisation uses iOS LocalAuthentication (Face ID / Touch ID / device passcode). Authentication is performed locally and is never uploaded.
- iOS includes a server-backed transfer activity screen.
- Added a native Android Jetpack Compose app with login/registration, profile setup, generated Trace.Pay ID, QR scanning, separate risk review, biometric/device-credential authorisation, ledger transfer and transfer history.
- Trace.Pay IDs now default to a readable unique handle based on the participant's full name, such as `kunal.kumar.dappu@tracepay`; collisions receive a numeric suffix. The ID is public-facing, so participants should understand it may reveal their name.
- Added a production Nginx web image (Vite build-time API URL), Azure Container Apps templates and an operations guide for always-on Container Apps, PostgreSQL Flexible Server and Azure Managed Redis.
- Remote push/APNs functionality remains removed.

## Honest operational status
- This ZIP is a deployable codebase/template, not a cloud resource already running. You must deploy it into your Azure subscription and configure secrets, managed database/cache, photo persistence, CORS and app API URLs.
- The default cloud URL is a placeholder until you replace it.
- External UPI / bank settlement is not connected. Ledger payments are internal Trace.Pay transfers only.
- Full Android Gradle build, full Xcode SDK build and cloud deployment require their respective SDKs and credentials and were not run in this packaging environment.
