# trace.pay 6 · Native build specification (iOS + Android)

The approved design is `prototype.html` in this folder. Open it in a browser: it is the source of truth for
every screen, colour, size, spacing, copy and animation. Match it screen for screen on both platforms.
Light theme only.

## 1. Brand
- Logo: `logo-official.png` (reference), `logo-mark.png` (app mark with the four corner squares), `logo-lockup.png` (mark + "trace.pay").
  Use the mark as the app icon artwork and on welcome, sign-in, lock screen, scanner top bar, QR centre. Use the lockup in the Home header.
- Signature details taken from the logo: the four small corner squares (violet `#8F6BFF`, or lime on dark/violet surfaces)
  on the scanner frame, device-lock artwork, My QR card and success mark; the pixel "t" as a faint texture on the balance card.

| Token | Value | Use |
|---|---|---|
| white | #FFFFFF | screen background |
| canvas | #F7F5FD | inputs, soft panels, keypad press |
| ink | #120A2B | text, primary button face |
| muted / faint | #6B6585 / #A39DBB | secondary text / captions |
| hair | #ECE8F5 | borders, dividers |
| violet | #5B2EFF (dark #3A17C9, darker #24108A, light #8F6BFF, soft #F1EDFF) | brand |
| lime | #C6FF3D | highlight on violet/dark only |
| good / warn / bad | #0A9D5A / #E59A00 / #E03E2D (+ bg #E6F6EE / #FFF4DC / #FDEAE7) | risk states |

Background: white with a soft violet radial glow top-right and a faint lime glow top-left (see `.screen` in the prototype).

Type: **Lexend** (bundle the font files; OFL licence). Scale: d1 34/600 (-3% tracking), d2 26/600, d3 20/600,
t1 16/500, t2 14.5/500, b1 14.5/400 muted, b2 12.5/400 muted, caps 11/500 +14% tracking. Tabular numbers for amounts.

## 2. Components
- **NeoPOP elevated button** (CRED style): flat face (ink, violet, white, danger, lime), 4 px right and bottom "plunk"
  edges in darker shades (violet edges under the ink face). Pressing translates the face 4 px and hides the edges.
  Height 56, full width with 4 px edge allowance. Disabled: pale lavender, no shadow.
- Icon button 44×44, radius 14, hairline border. Inputs 58 high, radius 16, canvas fill, violet 1.5 px border on focus.
- Segmented switch (Mobile | Email, Scan | Photos | My QR): canvas track, white selected pill.
- Cards radius 20, hairline border; soft panels radius 20 on canvas.
- Bottom sheet radius 32, grabber, sticky action area; scrim 36% ink with light blur.
- Floating tab bar: 16 px inset, 70 high, radius 24, translucent white with blur; centre Scan button 54×54, radius 17, violet, raised.

## 3. ScoreMeter (risk report)
- 270° arc, radius 96, stroke 16, rounded ends; track `canvas`; arc colour by band:
  0–24 Excellent (good), 25–49 Average (warn), 50–100 Poor (bad). 31 tick marks outside the arc (every 5th longer).
- Rounded-square dot at the arc end (22 pt white, shadow, 10 pt colour centre).
- Inner white circle (inset 44) with an 8 pt canvas gap ring and soft shadow: "RISK SCORE", big percentage (54/600),
  band pill, and "▲ 16 since last check" / "▼ …" / "No change" from the previous reading.
- Animate from the old reading (or 0) to the new reading over 1.4 s, ease-out cubic; count the number with it.
- Below: verdict panel (band colour on band background, read-aloud button), 2×2 facts (reports, payments seen,
  account type, confidence), "For this payment" (TraceShield reasons), "What raises the risk" and "What lowers the risk"
  (icon per factor code, explanation, 3-bar impact, signed points), "How the score changes" (counterfactuals).
  Factor rows animate in one by one (100 ms apart, after 700 ms).
- Data: `GET /api/v1/lookup?ref=<UPI ID or QR text>&amount=<amount>` (score, band, verdict, factors, counterfactuals,
  community, history, shield). Never skip the sheet: if lookup fails, show the rule result from `/api/v1/risk/check`.

Factor icons (SF Symbols / Material Symbols equivalents of the prototype icons): INBOUND_BREADTH people · OUTBOUND_BREADTH arrows-out ·
RAPID_ONWARD, LARGE_RELAY bolt · PASS_THROUGH, HIGH_FORWARDING swap · SHORT_DWELL timer · FAN_IN_OUT merge · STRUCTURING grid ·
ROUND_TRIP repeat · VICTIM_CONVERGENCE person-question · ESCALATION trending-up · SCAM_AMOUNTS rupee · MULE_LIFECYCLE history ·
COORDINATED link · DENSE_CORE, RING hexagon-grid · BRIDGE hub · ANOMALY pulse · *_REPORTS flag · COMPLAINTS report ·
INVESTIGATOR_FLAG shield-slash · INVESTIGATOR_CLEARED shield-check · VERIFIED_MERCHANT seal-check · REGULAR_CUSTOMERS storefront · NEW_ACCOUNT clock.

## 4. Screens (see prototype for exact layout)
1. **Welcome**: floating app mark with drop shadow, lockup, "Pay anyone. Know them first.", three feature rows, Create account / Sign in.
2. **Sign up** (4 steps, progress bar): (1) name + Mobile | Email switch (no OTP) → `POST /api/v1/auth/register`
   with `{mobile}` or `{email}` + password; (2) password with 4-segment strength meter and live checklist (12+, upper, number, symbol) + confirm;
   (3) live selfie (existing camera + on-device face detection, auto-capture) → `POST /api/v1/pilot/profile`;
   (4) device lock: shows the method the phone has, "Turn on <method>" triggers the system prompt; then "You're all set".
3. **Sign in**: Mobile | Email switch + password → `POST /api/v1/auth/login` with `{identifier, password}` → system device-lock prompt → Home.
4. **Lock screen**: shown on launch and on return from background when device lock is on; auto-prompts.
5. **Home**: lockup header, bell (unread dot), avatar; greeting; violet balance card (balance, UPI ID with copy,
   Scan & pay [lime], Pay [glass]); quick actions Check ID, My QR, History, Get help; monthly safety card (ring, checked /
   risky stopped / kept safe); red alert banner; Recent (3); Pay again; Know the scams cards. **No bank account details anywhere.**
6. **Scan**: dark camera, rounded frame with lime corner squares, beam animation, lock-on (frame shrinks to the code,
   turns lime, "found" pill with payee name, haptic), torch, 1×/2×/3× zoom, tray with Scan | Photos | My QR.
   Trace.Pay QR → Pay a member; any other UPI QR → Pay any UPI QR.
7. **Pay a member**: avatar, "First payment to this person" pill, large amount, keypad, "Check & continue" → risk sheet →
   cooling-off (first payment ≥ ₹5,000 to a new payee; 1/5/10 min setting) → device-lock prompt → success.
8. **Pay any UPI QR**: payee, amount (pre-filled from QR), note, "Pay with" list → risk sheet → hand off to the UPI app →
   on return "Did the payment go through?" → `POST /api/v1/external-payments` → success.
9. **Success**: green rounded-square check with lime corner squares, colour burst, amount, reference, Share receipt, Done.
10. **Activity**: monthly total with change vs last month, 7-day bars (today in violet), filters, list → **Payment details**
    (timeline: checked by trace.pay → paid via app → saved; UPI reference; Share receipt; Report a problem).
11. **Check**: UPI ID field (paste / scan), recent checks with risk pills, full risk report inline, Report this account.
12. **Alerts**, **Help** (1930, cybercrime.gov.in, bank, warn others), **Report** sheet (category chips with icons, details).
13. **Profile**: violet identity card (name, UPI ID, mobile or email), My QR / Copy ID; Security (Device lock toggle that
    requires the device prompt, signed-in devices, change password); Payment safety (cooling-off, daily limit, read aloud);
    App (language, privacy, help); Sign out.

## 5. Platform specifics
**Device lock: use only the phone's own authentication (no app PIN).**
- iOS: `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` (Face ID / Touch ID with passcode fallback). Label from `biometryType`.
- Android: `BiometricPrompt` with `setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)` (face, fingerprint,
  PIN, pattern or password, whatever the phone uses). If no lock is set, open security settings.

**UPI app list and hand-off**
- Android: query `Intent(ACTION_VIEW, "upi://pay")` and show each installed app with its **real icon and label from
  `PackageManager`** (`loadIcon`/`loadLabel`); add `<queries>` for the upi scheme. Launch with `startActivityForResult`
  and parse the response (`Status`, `txnId`); if none, ask the user to confirm.
- iOS: tiles with app colour and initial (other apps' icons are not available on iOS); open `gpay://upi/pay`,
  `phonepe://pay`, `paytmmp://pay`, `bhim://upi/pay` (first one `canOpenURL` accepts; schemes listed in
  `LSApplicationQueriesSchemes`); on return to foreground ask "Did the payment go through?". Never present two alerts on one view.

**Scanner**: iOS AVFoundation + Vision; Android CameraX + ML Kit barcode. Parse any UPI QR (`pa`, `pn`, `am`, `tn`).

**Motion**: screen content rises in (18 px, 0.55 s, 50 ms stagger); sheets slide up with a soft spring; button press 70 ms;
ScoreMeter 1.4 s; factor rows staggered; success pop + check draw + burst; scanner beam and lock-on spring.
Respect Reduce Motion.

## 6. API (already deployed in 5.2.x; mobile sign-in added in 5.3)
`POST /auth/register {mobile|email, password}` · `POST /auth/login {identifier, password}` · `POST /auth/refresh` ·
`GET/POST /pilot/profile` · `GET /pilot/wallet` · `GET /pilot/transfers` · `GET /pilot/recipients/{vpa}` ·
`POST /risk/check` · `GET /lookup?ref=&amount=` · `POST /pilot/transfers` · `GET/POST /external-payments` ·
`POST /community/reports` (all under `/api/v1`).

## 7. Done means
Builds with zero errors and zero warnings on both platforms, runs in Simulator/emulator and on a device, every screen
matches the prototype side by side, and every flow in the prototype's guide works against the live API.
