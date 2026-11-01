Paste this into Claude Code, opened in the Tracepay_NEW folder:

---
Rebuild the iOS app (ios-app/) and the Android app (android-app/) to match the approved design in
design/app-v6/. Read design/app-v6/BUILD_SPEC.md fully, then open design/app-v6/prototype.html and study every screen
(it is the source of truth for layout, sizes, colours, copy and motion).

Work in this order, building and running after each step and fixing every error and warning before moving on:
1. Design system per platform: colour tokens, Lexend font (bundle it), type scale, NeoPOP elevated button, inputs,
   segmented switch, cards, bottom sheet, floating tab bar, corner-squares modifier. Add the logo images from design/app-v6.
2. Auth: welcome, sign-up (mobile or email, no OTP, password strength, live selfie, device lock), sign-in, lock screen.
   Device lock uses only the system: LAContext .deviceOwnerAuthentication on iOS, BiometricPrompt with
   BIOMETRIC_STRONG or DEVICE_CREDENTIAL on Android.
3. Home, Activity, Payment details, Alerts, Help, Profile.
4. ScoreMeter risk report exactly as specified, driven by GET /api/v1/lookup, with the fallback to /risk/check.
5. Scan (lock-on animation, torch, zoom, photos, My QR), Pay a member (keypad, cooling-off, device-lock confirm),
   Pay any UPI QR (Android: real installed UPI app icons from PackageManager; iOS: URL schemes; confirm on return), Success.
6. Run both apps against the live API, go through every flow in the prototype guide, and compare each screen side by side
   with the prototype. Fix any difference.
Keep existing working code (APIClient session handling, selfie capture, QR parsing) where it fits; replace the old UI.
Remove the old screens once the new ones are wired in. Do not add bank account details anywhere.
---
