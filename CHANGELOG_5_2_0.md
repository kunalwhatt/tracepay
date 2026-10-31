# Trace.Pay 5.2.0: Safety layer stage 1 (risk pop-up, any UPI QR, community reports, live refresh fix)

## Risk pop-up before every payment (iOS + Android)
- An animated bottom sheet opens automatically on the payment review: TraceScore gauge sweeps up and counts,
  verdict ("High risk", "Risky", "Be careful", "No warning signs"), member / verified-merchant badges,
  report count, confidence, TraceShield reasons, every factor with its points (animated in one by one, with
  growing bars), "what would change it", and Pay / Cancel / Report.

## Pay any UPI QR (GPay, PhonePe, Paytm, BHIM, bank apps)
- Scanning a non-Trace.Pay UPI QR opens "Pay any UPI QR": amount (pre-filled from the QR), check, risk pop-up,
  then hand-off to the user's UPI app.
- Android: system chooser of installed UPI apps; the UPI response (Status, txnId) is read on return and recorded.
  If the app does not report back, the user confirms. "Open your UPI app and scan there" buttons always work.
- iOS: Google Pay / PhonePe / Paytm / any UPI app; on return to Trace.Pay the user confirms and it is recorded.
- Note: banks may decline intent payments started from apps that are not registered merchants (NPCI rules).
  Option A (payment-gateway merchant account) removes this; the code is ready to plug one in.

## Truecaller-style safety layer (backend)
- `GET /api/v1/lookup?ref=` any UPI ID or UPI QR text: one explained score combining TraceScore behaviour with
  community reports, confirmed reports, complaints, investigator decisions and verified-merchant trust.
  Members see other people's IDs masked.
- `POST/GET/PATCH /api/v1/community/reports`: users report scams; investigators confirm or reject.
- `PATCH /api/v1/pilot/merchants/{id}/verify`: verified merchants get a ✓ and a lower score.
- `POST/GET /api/v1/external-payments`: payments made in other UPI apps; successful ones become evidence records.
- New tables `scam_reports`, `external_payments`; `pilot_merchants.verified` column (created automatically).

## Web console
- Live refresh fixed: tokens renew every 8 minutes, WebSocket heartbeat every 25 s, debounced reload on all event
  types (including external payments and community reports), clean sign-out when a session ends, live indicator.
- New **Safety Center**: look up any UPI ID with the full explained score, moderate community reports,
  verify merchants.

## Tests
38 backend tests pass (including UPI QR parsing and the community-adjusted verdict).
