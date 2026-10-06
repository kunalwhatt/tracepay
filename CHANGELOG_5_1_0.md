# Trace.Pay 5.1.0: mobile redesign, live selfie, camera-first QR, TraceShield in the apps

## Android (focus of this release)
- **Camera-first QR**: tapping Scan opens the live camera (CameraX + on-device ML Kit). The animated scan frame,
  torch and **Import from photos** are inside the camera view; "My QR" switches to your code. Non-Trace.Pay QR
  codes show a reason and scanning resumes automatically.
- **Live selfie with face detection** (no gallery): front camera with real-time guidance ("move closer", "only one
  face", "look straight", "keep your eyes open") and automatic capture once the face is steady. The photo is
  rotated upright, mirrored and resized before upload.
- **New sign-in / create account**: animated gradient hero, sliding sign-in / create switch, icons in fields,
  show / hide password, strength meter with checklist, confirm password, clear errors.
- **New 3-step profile setup** (selfie → about you → gender) with progress ticks.
- **TraceShield card** on the payment review with plain reasons (first-time payee, unusual amount, new account,
  many first-time payers, high TraceScore, complaints, investigator flags). Advisory: the user decides.
- New libraries: CameraX 1.4.1, ML Kit barcode-scanning 17.3.0 and face-detection 16.1.7, ExifInterface.

## iOS
- **Camera-first QR**: the Scan tab opens the camera directly, with the animated frame, torch, "Import from photos"
  and "Show my QR" inside it.
- **Live selfie** with Apple Vision face detection and automatic capture; the photo library is no longer used.
- **New sign-in / create account** with the same design as Android (matched-geometry switch, strength meter,
  confirm password) and the **TraceShield card** on the review step.

## Both apps and the console
- "Pilot", "sandbox", "simulation" and "TraceBank" wording replaced across both apps.
- The payer's risk check sends the amount so TraceShield can compare it with the payer's usual payments.
- **Web console**: User Management shows each member's live selfie (fetched with the investigator's token, cached
  for the session, every view written to the audit log).
