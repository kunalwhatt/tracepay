# Trace.Pay Studio 3.0

## Design and experience
- Applied the supplied Trace.Pay wordmark and emblem to the web console and iOS asset catalog.
- Reworked web console surfaces around a white, green and electric-blue design system with responsive layouts, live-state motion, gradient actions and updated graph semantics.
- Refined iOS language and the green/blue palette; added pull-to-refresh to the home dashboard and tracked refresh outcomes.
- Preserved the native SwiftUI app, existing account flow, QR flow, haptics, and payment-result animation components.

## Research and event flow
- Temporal graph now includes successful internal-ledger transfers as confirmed directed edges and failed attempts as separate dashed edges.
- Explainable risk assessment includes successful internal-ledger transfers alongside imported, source-linked transaction records.
- Both user and administrator transfers emit persistent audit activity and a WebSocket activity event so the web activity feed can update.
- Research context remains provenance-first, evidence-gap aware, and advisory.

## Scope note
The interface is styled as a consumer payment application, but Trace.Pay IDs and internal ledger transfers are not a bank-issued UPI ID or external bank settlement. External payment rails require authorised provider integration.
