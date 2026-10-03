# Trace.Pay Studio 3.2 — Full Onboarding, Push and UI Refresh

## iOS onboarding
- Email/password registration remains the first step; Apple and Google sign-in are not presented.
- Registration requires a 12+ character password with uppercase, numeric and special characters (server enforced).
- Added a guided personal-profile step: full name validation, 18+ date picker and required gender selection.
- Added camera capture and system photo-library selection, preview, Retake and Use This Photo states.
- Apple Vision checks for exactly one face before the user can continue.
- The API independently checks MIME type, file signature, dimensions, 4 MB size limit and exactly one detected face.
- Account/Trace.Pay ID is assigned by the backend; the client cannot choose the ID.

## Secure photo storage
- Original JPEG bytes are encrypted using the configured Fernet key before being written to a private persistent volume.
- The photo key is not returned in profile JSON; photo retrieval requires the account's bearer token.
- The admin directory shows photo-check status but does not expose photo bytes.
- Face detection is not face matching or liveness detection.


## Web and visual refresh
- Refined responsive surfaces, field focus states, hover/tap feedback, staggered entry transitions, modal motion and reduced-motion support.
- User directory includes gender and face-check status; sensitive photo bytes remain private.
- Workspace copy now uses operations/account language. It still accurately states that external bank settlement is not connected.
- Live WebSocket transfer/activity events and periodic refresh remain enabled.

## Validation performed
- Python syntax compilation passed for `main.py`, `models.py`, and `schemas.py`.
- Pydantic password validation checks passed for a strong password and three weak-password cases.
- Swift source syntax parsing passed for all Swift files with `swiftc -frontend -parse`.
- Full Docker/API runtime and iOS SDK build could not be run in this build environment. Install/build and verify with Docker and Xcode on the target Mac.
