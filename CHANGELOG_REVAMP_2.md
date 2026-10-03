# Trace.Pay Pilot Revamp 2.0

## Experience
- Rebuilt the web console around a light-first, Gen-Z fintech visual system: electric violet, lime, mint, soft blue, subtle motion, rounded cards, responsive navigation, and high-contrast typography.
- Added pilot users, merchants, pilot transfers, graph explorer, risk studio, source-backed transactions, and ingestion screens.
- Added a full-screen animated iOS risk-assessment overlay and refreshed the pilot identity setup.

## Pilot backend
- Added pilot profile, merchant, and simulation transfer tables.
- Added consent-gated profile creation with encrypted-at-rest name, date of birth, bank name, and account last-four.
- Added a participant directory that excludes date of birth.
- Added custom and random-batch simulation records with audit events and idempotency keys.
- Added Redis-backed per-user transfer rate limiting and pilot health reporting.
- Changed public self-registration to the `pilot_user` role so consumer accounts do not receive operations-console permissions.

## Not enabled in this build
- Actual bank/UPI payment execution or settlement confirmation.
- Google OAuth / Sign in with Apple provider verification.
- Live selfie or KYC verification.
- Live bank feeds or transaction monitoring from other payment apps.

These integrations require authorised providers, credentials, server-side verification, and security/legal review. The current pilot is not a production payment system.
