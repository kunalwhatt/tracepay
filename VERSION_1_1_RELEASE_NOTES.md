# Trace.Pay 1.1.0 — Full UI/UX Refresh and Stability Pass

## What changed
- Replaced the web console stylesheet with a cohesive light-first design system: clearer navigation, typography, spacing, data tables, forms, risk panels, service cards, modals, and responsive layouts.
- Reworked small-screen navigation so the workspace sections remain accessible through a horizontally scrollable navigation bar.
- Updated web page metadata, API version, and iOS app version to 1.1.
- Kept the existing API paths and data model to avoid breaking the web console/backend contract.
- Removed stale push-notification test instructions. Remote push notifications remain excluded.
- Confirmed `LocalUnlockStore` is declared exactly once in `APIClient.swift` and removed APNs/push APIs from the iOS source.
- Removed generated Python bytecode from the distribution.

## Validation performed
- All four Swift source files passed Swift frontend syntax parsing.
- Backend Python modules passed `py_compile`.
- The iOS plist and Docker Compose YAML were checked for valid structure.
- Source checks confirmed one `LocalUnlockStore` declaration and no push-registration APIs or APNs entitlement in the iOS/backend source.
- A production Vite build could not be run in this environment because npm registry DNS/network access failed (`EAI_AGAIN`). Run `npm install` and `npm run build` on a connected development machine.
- A full iOS SDK build/signing check must be performed in Xcode on macOS. Swift syntax parsing does not replace an Xcode build.

## Important
Use a clean extraction of this release rather than merging files into the old Studio 3.2 folder. Keep your existing `.env` secure and back up your database before upgrading. Do not run `docker compose down -v` if you need to preserve data.
