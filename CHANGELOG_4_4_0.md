# Trace.Pay 4.4.0 — mobile apps rebuilt to the Play designs, sessions, scale-out

Builds on 4.3.0 (see `CHANGELOG_4_3_0.md`).

## iOS and Android, screen by screen
Both apps now follow the iOS/Android Play design files:
- **Home:** greeting with a live "Session mm:ss" chip, violet TraceBank balance card with hide/show, Pay / Scan / My QR / Activity tiles, your Trace.Pay ID with Copy ID, risk-engine card, "How a payment works", Pay again avatars from your recent payees, and recent transfers.
- **Pay flow (full screen):** recipient (type a name; `@tracepay` is added for you) → amount keypad (two decimals, ₹1,00,000 pilot limit, balance check) → risk review (level card, "Why this category", records / rule / as-of tiles, disclaimer) → Face ID or biometric confirmation screen → success or "Payment not completed" result with the TraceBank reference.
- **Scan / My QR:** one screen with a segmented control. Scanning accepts only Trace.Pay IDs. My QR renders a real QR (`tracepay://pay?pa=name@tracepay`) with Copy ID and Share.
- **Activity:** All / Sent / Received / Failed filters; incoming payments now appear (previously only sent ones did).
- **Profile:** identity card, My QR shortcut, Face ID and risk review shown as always on, haptics toggle (iOS), account details, log-out confirmation.
- **Floating tab bar** with the lime selected state.
- The design's "Pending" filter is omitted: TraceBank transfers are never pending. The design's `TRP-4821-AM` IDs are replaced by `name@tracepay`.

## Sessions
- New `POST /api/v1/auth/refresh` renews a still-valid token; sessions end 12 hours after sign-in. Apps renew automatically when under five minutes remain.
- When the server rejects a session, the apps return to sign-in with a "Your session ended" banner instead of failing silently, and iOS no longer offers an expired token for Face ID unlock.

## Bugs fixed
- Android could not compile: `BiometricPrompt` needs a `FragmentActivity`; `toRequestBody` was not imported; unused `Api.kt` redeclared `Profile`, `Wallet` and `Transfer`.
- Biometric cancel on Android left the payment screen stuck; it now returns to review with the reason.
- iOS: a committed payment could show an error if the follow-up wallet refresh failed.
- Participants only saw transfers they sent; received transfers now appear.
- Android launcher scan failures were silent; they now show a message.

## Scale-out
- Live WebSocket events are relayed between API replicas through Redis pub/sub (`tracepay:live`). The Azure template is back to `maxReplicas: 5`.

## Still to verify on your machines
The Swift and Kotlin code could not be compiled in the environment that produced this release, and the API was not run against PostgreSQL or Redis. Build both apps in Xcode and Android Studio and run `docker compose up --build` before the demo. Known remaining item: schema changes still use startup `ALTER TABLE`; move to Alembic before production.
