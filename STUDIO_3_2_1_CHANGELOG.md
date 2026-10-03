# Trace.Pay Studio 3.2.1 — Remote notifications removed

- Removed APNs provider delivery, device-token registration, test-notification and unregister endpoints.
- Removed iOS remote notification permission prompts, APNs registration delegate, token registration and test-alert controls.
- Removed the push-notification section from Settings and the APNs entitlement from the Xcode target.
- Removed APNs environment variables and the secrets-directory mount from Docker Compose.
- Removed the unused `httpx[http2]` dependency that was only needed for APNs delivery.
- Kept in-app status updates, WebSocket console events, and local haptic feedback for user interactions.
- No Apple Developer Program membership or `.p8` key is required for this version.

Existing `push_devices` tables, if present in an existing database, are left untouched and unused. No database volumes or transaction records are deleted.
