# Trace.Pay iOS redesign — 2.1

This update replaces the prior iOS screen composition with a green/blue, light-first native SwiftUI experience aligned with the Trace.Pay web console.

## Included

- Rebuilt sign-in / registration presentation with a green-blue visual system, animated hero art, rounded form fields, responsive states, and haptic feedback.
- Keychain-backed session persistence and native iOS device authentication (`LocalAuthentication`) using Face ID or the device passcode to unlock a saved session.
- A new home dashboard with the live pilot wallet balance and assigned pilot ID, plus Scan, Send, and My QR actions.
- A profile flow that requests no client-generated VPA. FastAPI assigns the unique pilot ID and returns it as the authoritative identifier.
- A per-profile QR generated locally with Core Image from the server-assigned ID, registered display name and profile ID. It is a scannable Trace.Pay pilot QR, not a bank-issued UPI QR.
- A backend recipient lookup that displays the registered participant/merchant name after scanning and before risk review.
- Animated success/failure payment states with large amount typography, status-specific haptics, and a system map in Profile.
- An internal pilot transfer flow that assesses the recipient, displays explainable risk reasons, asks for confirmation, and submits the transfer to the existing FastAPI pilot-ledger endpoint.
- Profile, pilot wallet information, security settings, account switching, QR sharing, empty/error/loading states, and an updated QR scanner presentation.
- Green, mint, and electric-blue design tokens, layered gradients, soft depth, animated transitions, and press feedback.

## Important integration notes

- The app continues to use the existing FastAPI endpoints and PostgreSQL-backed pilot ledger. No sample transactions or fake balances were added.
- The app is a closed-loop pilot. `@tracepay` IDs and `tracepay://` QR payloads are not real UPI addresses. A transfer success refers only to the persisted internal pilot ledger.
- Google and Apple sign-in buttons are included in the refreshed UI, but they are not yet connected to an authentication provider. The current backend exposes email/password authentication only. To enable social sign-in, configure the relevant Google/Apple app identifiers and implement server-side identity-token verification and account linking; do not trust a client-supplied email alone.
- Face ID/device-passcode unlock is implemented using Apple's LocalAuthentication framework. Biometric data never leaves iOS.
- This environment is Linux-based and does not include Xcode/iOS SDK, so a full iOS build could not be run here. The Swift source files passed Swift frontend syntax parsing; open the project in Xcode on macOS and build/test on a simulator or device before use.

## Open in Xcode

1. Unzip the full project.
2. Open `ios-app/TracePay.xcodeproj` in Xcode.
3. Select the `TracePay` scheme and an iOS 17+ simulator or device.
4. Confirm `TRACEPAY_API_BASE_URL` in `ios-app/TracePay/Info.plist`. Use the API URL reachable from the device. On a physical iPhone, use your Mac's LAN IP or a deployed HTTPS API URL rather than `127.0.0.1`.
5. Build with **Product → Build** (⌘B), then test registration, profile creation, QR scanning, risk check, internal transfer, lock/unlock, and sign-out.

## Existing account data

The app code changes do not delete or reset PostgreSQL data. Database schema fixes previously applied to the running database are not automatically turned into migrations by this iOS-only redesign.


## Revision 2.2 addendum (2026-09-29)

See `README_REBUILT_IOS.md` and `../CHANGELOG_TRACEPAY_LIVE_QR_OBSERVABILITY.md` for server-assigned QR identity, recipient resolution, milestone telemetry, system observability, and the encrypted profile-field migration.
