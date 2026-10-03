# Trace.Pay 1.1.1 — Graph readability and evidence clarity

## Changes
- Replaced the overlapping circular SVG layout with shortest-hop columns and spaced account cards.
- Added horizontal scrolling for larger networks and tooltips on edges/nodes.
- Added amount labels only for smaller graphs to avoid clutter.
- Added a source-backed transaction table below the graph with direction, amount, outcome, record/source reference, and timestamp.
- Distinguished confirmed internal-ledger transfers, imported/source-linked records, and failed attempts visually.
- Updated web-console package version to 1.1.1.

## Data integrity boundary
The graph renders records returned by the backend: persisted successful internal Trace.Pay ledger transfers, failed attempts marked as attempts, and authorised source records imported into this instance. It does not connect to banks or NPCI/UPI rails and cannot independently observe payments completed in third-party apps. External UPI execution and authoritative settlement status require an authorised bank/payment-service-provider integration. No sample transactions are added by this release.

## Validation
The JSX source and CSS were updated. A full npm production build and full Xcode SDK build require dependency access and the user's local build environment; they are not claimed as completed here.
