# Trace.Pay V3 — Complete UI/UX Rebuild

This package is a **from-scratch visual and interaction redesign** of the existing Trace.Pay pilot surfaces.

### Surfaces rebuilt
- Web investigator console
- Native iOS SwiftUI app
- Native Android Jetpack Compose app

### New product direction
The old visual language is intentionally not preserved. V3 uses a premium light-first fintech system with midnight navy, electric indigo, signal blue and mint; Space Grotesk/DM Sans typography; large editorial headings; high-radius surfaces; animated ambient backgrounds; live pulses; graph motion; responsive transitions; and tactile payment states.

### Payment UX
`Home → Pay/Scan → Recipient → Separate Risk Review → Biometric Authorisation → Recorded Transfer → Activity`

Risk assessment is not buried in the pay confirmation. The recipient is entered/scanned first, then the backend assessment is shown on its own review page with reasons, rule version, observed-record count and advisory disclaimer.

### Mobile transaction history
Both mobile apps now expose server-backed TraceBank transfer activity rather than a fake local history.

### Biometric payment confirmation
- iOS: LocalAuthentication (`deviceOwnerAuthentication`) before `makePilotTransfer`.
- Android: AndroidX BiometricPrompt before `pay`.

The biometric step authorises the **internal Trace.Pay pilot ledger only**. It does not represent real bank/UPI settlement.

### Risk semantics
The UI renders backend risk output. It does not invent its own fraud score. LOW/MEDIUM/HIGH/CRITICAL/UNKNOWN are displayed with distinct visual states; evidence gaps remain unknown rather than being treated as proof of no transaction.

## Validation note
This environment does not contain Xcode or Android Studio/Gradle, and npm dependency installation could not complete within the available build window. Therefore this package has **not** been honestly represented as a fully device-built/compiled release here. The source redesign is packaged for opening in Xcode, Android Studio and the web project.
