# Trace.Pay iOS — Studio 3.2

Native SwiftUI app for Trace.Pay accounts, QR-based recipient lookup, internal-ledger transfers, explainable risk review, and profile/security settings. Design language is light-first with indigo/electric-blue and mint accents, tactile transitions, haptics, and reduced visual clutter.

## Registration

- Email/password credentials; no Apple or Google sign-in buttons.
- Server-enforced password requirements: 12+ characters, uppercase, number, and special character.
- Guided personal details: name without numbers, 18+ date picker, and gender selection.
- Face-photo step with camera capture or photo-library selection, preview, Retake, and Use This Photo.
- Apple Vision checks for exactly one face on-device; the backend repeats the check and image validation.
- The backend assigns the Trace.Pay ID and internal profile reference automatically.

## Photo handling

The iOS app converts the selected image to JPEG, checks that the compressed upload is at most 4 MB, and runs face detection before showing the preview. The backend accepts JPEG/PNG/WebP, checks the signature and dimensions, and requires exactly one detected face. The image is encrypted at rest in a private Docker volume. Face detection is not face matching, liveness detection, or identity verification.


## Build in Xcode

1. Open `TracePay.xcodeproj`.
2. Select the `TracePay` scheme and an iOS 17+ simulator/device.
3. Confirm `TracePay/Info.plist` → `TRACEPAY_API_BASE_URL`. Use the Mac localhost URL for Simulator, or the Mac LAN IP/HTTPS API for a physical iPhone.
4. Select your Apple development team for device testing. Remote push notifications are not included in this build.
5. Build with **⌘B**, then test onboarding, camera/gallery, one-face rejection, account creation, Face ID/MPIN unlock, QR scanning, and the risk assessment flow.

## Payment boundary

A `SUCCESS` result is a successful debit/credit in the Trace.Pay internal ledger. External bank accounts and UPI settlement rails are not integrated. The app does not request UPI PINs or banking passwords.

## Validation

Swift syntax parsing passed in the source-build environment. A full iOS SDK build and device signing must be run in Xcode on the target Mac. Remote push notifications are intentionally excluded.
