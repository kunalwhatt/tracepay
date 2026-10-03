# Trace.Pay iOS Build Fix 3.2.2

This package addresses the errors shown in the Xcode issue navigator:

- `LocalUnlockStore` is defined in `APIClient.swift`, where authentication/session code uses it, and remains available to `ContentView.swift`.
- Profile setup calls `createPilotProfile` with all required arguments: `fullName`, `dateOfBirth`, `gender`, `photoData`, `consentProfile`, and `consentLedger`.
- The Xcode project has no Push Notifications capability or `aps-environment` entitlement. Remote push/APNs code is not included.

## Open the correct project

1. Extract this archive into a new folder (do not merge it into the old project).
2. Open `TracePay_Studio_3.2/ios-app/TracePay.xcodeproj` from the extracted folder.
3. Select the `TracePay` target → **Signing & Capabilities**. Choose your Personal Team. The project should not list **Push Notifications**. If it appears, you have opened the old project or manually added the capability; remove it.
4. If Xcode reports a bundle identifier conflict, change `tech.tracepay.ios` to a unique identifier you control.
5. Choose an iPhone simulator and build. For a device, keep **Automatically manage signing** enabled and select your Personal Team.

The source files have been syntax-parsed, and the project file was checked for push entitlements. A full Xcode/iOS SDK build cannot be performed in this packaging environment.
