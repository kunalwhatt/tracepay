# Trace.Pay Studio 3.1 — targeted UX and intelligence refresh

## Included
- Fixed the missing `Sparkles` icon import in the web console source.
- Intelligence > Transactions now shows persisted Trace.Pay internal-ledger transfers separately from authorised imported transaction records. It does not conflate the two evidence types.
- Web console subscribes to live transfer events, refreshes the graph after events, reconciles every 15 seconds, and refreshes when the browser tab becomes visible again.
- iOS account access no longer displays non-functional Google or Apple sign-in buttons.
- iOS bottom navigation has a constrained height so the raised QR action does not inflate the tab bar.
- iOS profile setup limits the date picker to people aged 18+ and validates names against letters, spaces and common name punctuation.
- The web intelligence tables remain horizontally scrollable on narrow screens.

## Important items not completed by this targeted update
- The requested gender field and face-photo capture/upload flow still require an end-to-end API/schema change and must be added before treating onboarding as complete.
- Face-photo validation should use Apple's Vision face detection on-device (exactly one face) and server-side format/size validation. Do not store photos as unbounded plaintext/base64 or treat face detection as identity verification.
- This application uses an internal Trace.Pay ledger. Its transfers can be persisted and displayed in intelligence, but this does not connect to UPI rails or establish external bank settlement. Keep this distinction available in product disclosures and transaction detail.

## Apply
Extract this archive to a new directory, then use the existing `.env` values and database volume. Do not run `docker compose down -v`.
