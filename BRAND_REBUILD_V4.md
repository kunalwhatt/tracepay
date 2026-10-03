# Trace.Pay 4.0 — Brand + Cross-platform UI rebuild

This rebuild keeps the existing FastAPI/PostgreSQL/NetworkX transaction intelligence backend and replaces the presentation layer with a shared Trace.Pay visual system based on the supplied `trace.pay` logo.

## Brand
- Warm ivory: `#F7F3EB`
- Paper: `#FFFDF9`
- Ink: `#0E0D0C`
- Coral: `#FF5742`
- Coral soft: `#FFE5DE`
- Mint: `#DFF6ED`
- Green: `#14764F`
- Muted: `#77736C`

The same palette is used by web, iOS and Android.

## Application flows
### Web investigator console
Dashboard → Case Management → Transaction Search → Graph Analysis → Account Analysis → Risk Alerts → Reports → Data Ingestion → User Management → System Logs → Payer Simulator.

The dashboard polls live backend state and presents persisted transactions, pilot ledger activity, ingestion jobs, evidence posture and risk-assessment events. Graph Analysis calls `/api/v1/graph/paths/{account_ref}`. Data Ingestion calls `/api/v1/ingestion/csv`.

### Mobile user flow
Login/Register → Profile onboarding → Home → Pay/Scan QR → recipient lookup → separate Risk Review page → biometric confirmation → internal TraceBank ledger transfer → Activity/receipt → Profile/Security.

Registration requires email/password first, then profile details, date of birth 18+, gender, a single-face photo and two explicit pilot consents.

### Risk categories
The backend is authoritative. Current rule logic (`rules-v1`) examines records available in the preceding 24 hours:
- `review`: at least two configured pattern reasons are triggered.
- `caution`: one configured pattern reason is triggered.
- `no_known_warning`: observed records exist but no configured rule is triggered.
- `insufficient_information`: no records are available for the recipient.

Current configured patterns include multiple distinct incoming counterparties, multiple distinct outgoing counterparties, and overlap of incoming/outgoing activity within a short observation window. The UI shows reasons, rule version, observed record count and data-as-of time. It does not represent the advisory as proof of fraud or as a safety guarantee.

## Validation status
- iOS Swift files are syntax parsed in the build environment.
- Full iOS framework compilation/signing must still be performed by Xcode on macOS.
- Android and web dependencies are not installed in this environment, so a full Gradle/Vite build is not claimed here.
- Docker Hub/network availability can affect container builds independently of source correctness.
