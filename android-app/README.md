# Trace.Pay Android 2.0.0

Native Android client built with Kotlin, Jetpack Compose, Retrofit and Android BiometricPrompt. It includes account registration/sign-in, server-side profile creation with photo upload, generated `@tracepay` ID, QR scanning, recipient lookup, a dedicated risk-review page, biometric/device-credential authorisation, internal-ledger transfer and server-backed activity history.

## Open/build

1. Install Android Studio (current stable) with Android SDK Platform 35 and JDK 17.
2. Open this `android-app` folder as a project and allow Gradle sync.
3. In `app/build.gradle.kts`, replace `https://REPLACE-WITH-YOUR-API.azurecontainerapps.io/` in `TRACEPAY_API_BASE_URL` with your deployed HTTPS API origin. For emulator-only local testing, use `http://10.0.2.2:8000/` and temporarily configure cleartext networking only in a debug-only manifest; do not ship HTTP in a release build.
4. Build and run on an Android device or emulator with Google Play services. QR scanning uses Google Code Scanner. Biometric/device credential authentication is handled by Android and no biometric data is uploaded.

## Notes

- Android app uses the existing FastAPI endpoints; it does not create a bank/UPI connection.
- Profile photo uploads are sent using their detected MIME type; backend validates format and exactly-one-face detection.
- This source has not been built with Gradle in this packaging environment because the Android SDK/Gradle toolchain is not installed here. Run Gradle sync/build in Android Studio before distribution.
