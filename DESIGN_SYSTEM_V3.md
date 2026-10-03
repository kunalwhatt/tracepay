# Trace.Pay V3 — New Product Design System

This rebuild replaces the previous visual system rather than layering another skin over it.

## Brand direction
- **Concept:** payment confidence + evidence intelligence.
- **Tone:** premium fintech, calm, cinematic, precise; not a generic banking template.
- **Palette:** midnight navy `#0B1220`, electric indigo `#5046E5`, signal blue `#4D8DFF`, mint `#55E6BA`, paper `#F5F7FB`.
- **Typography:** Space Grotesk for display/brand numbers, DM Sans for operational text.
- **Surfaces:** high-radius cards, soft borders, restrained shadows, glass only where it adds depth.
- **Motion:** live pulse, ambient aurora, animated graph nodes, chart bars, page cross-fades, bottom-sheet slide, hover/press elevation.

## Payment journey
1. Home → Pay / Scan QR.
2. Recipient entry or QR scan.
3. Recipient lookup.
4. **Separate risk review page** — no risk assessment is hidden inside the confirmation screen.
5. Explainable reasons, rule version, observed-record count, disclaimer.
6. Final **Face ID / Android biometric** confirmation.
7. Server-backed internal ledger transfer.
8. Transaction appears immediately in mobile Activity and web console.

## Risk category presentation
The client does not invent a risk score. It renders the backend's `level`, `reasons`, `observed_transaction_count`, `rule_version`, and `disclaimer`.

Suggested semantic treatment:
- **LOW:** no configured elevated signals observed.
- **MEDIUM:** one or more configured warning signals observed.
- **HIGH/CRITICAL:** configured elevated signals require stronger review.
- **UNKNOWN:** insufficient evidence or unavailable data; never treat missing records as proof that no transfer occurred.

The actual category thresholds/rules remain server-side and versioned. The UI exposes the rule version so an investigator can reproduce the assessment.

## Safety boundary
TraceBank is an internal pilot ledger. The apps do not collect a real UPI PIN, do not claim bank settlement, and do not infer successful external UPI payment from a handoff.
