# iOS Rebuild 2.1

- Replaced the old iOS UI with a full green/blue SwiftUI redesign.
- Added a redesigned authentication screen, automatic pilot VPA assignment, live pilot wallet card, custom bottom navigation, scan/send/QR flows, and profile/settings pages.
- Added local Core Image QR generation for Trace.Pay pilot payloads and QR sharing.
- Kept risk assessment and internal transfers connected to the existing API.
- Removed device-email lockouts from login/registration so another account can be used after signing out.
- Added Face ID/device passcode unlock for a saved session.
- Updated scanner copy to distinguish pilot QR handling from real UPI settlement.
- Documented that Google/Apple sign-in UI still needs provider credentials and backend token verification.
