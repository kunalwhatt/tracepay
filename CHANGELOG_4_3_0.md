# Trace.Pay 4.3.0 — pixel-t identity, real evidence graph, Phase 1 fixes

Includes everything from 4.2.0 (never released separately).

## New identity (4.3.0)
- Pixel-"t" mark on violet `#5B2EFF` with a lime `#C6FF3D` pixel; palette ink `#14092E`, lavender `#F3EEFF`/`#E4DCFF`, Bricolage Grotesque type.
- `scripts/generate_brand_assets.py` renders every asset from one pixel grid: web SVG favicon and marks, iOS AppIcon (1024, full-bleed) and TracePayMark, Android `tracepay_mark` and launcher icons for all densities (the app previously had no launcher icon).
- Web console: floating white sidebar with lime active state, lavender hero, violet sign-in panel ("Follow the money. Show your proof."), light graph canvas with pill-shaped accounts (traced account in lime), readable type sizes throughout.
- iOS and Android: all screens re-themed through the existing colour tokens; lockup is the new mark plus wordmark.
- Design note: the mockups show IDs like `TRP-4821-AM`. Per the project requirement, Trace.Pay IDs remain `name@tracepay`.

## Trace.Pay IDs are `name@tracepay` only (4.3.0)
- One rule (`backend/app/ids.py`, mirrored in web, iOS and Android): a bare name gets `@tracepay`; scanned `upi://` or `tracepay://` QR codes are read from `pa=`; any other handle (for example `@okhdfc`) is refused with a clear message.
- Enforced for transfers, admin transfers, merchant registration, wallet funding, recipient lookup and payer risk checks.
- Not enforced for ingested datasets or investigator searches: external accounts in authorised records are evidence references, not Trace.Pay IDs.
- Generated IDs strip accents so names like "Zoë" still produce a valid ID.

## Real graph and charts (4.2.0)
- Graph Analysis draws actual transfers: left-to-right money flow by hop, line colour = evidence state, thickness = amount, parallel transfers fanned out, click any line for file/sheet/row/job provenance, click any account for totals and observed-flow difference, time replay, zoom/pan, timeline table, IST times.
- Dashboard: data-anchored daily activity (transfers or volume), latest risk level per recipient, evidence quality, ledger and conflict counts.
- Account Analysis: per-account behaviour metrics, 30-day chart, top counterparties, rules-v1 recomputed at last activity with evidence.

## Bugs fixed (4.2.0)
- Mobile apps showed SUCCESS for FAILED transfers; they now show NOT COMPLETED with the reason.
- Retrying a payment could move money twice; idempotency keys now live for one payment attempt.
- Self-registered pilot users could read all investigator data and every live event; endpoints are role-locked and live events are scoped per user.
- DD/MM dates were read as MM/DD; ISO dates stay year-first and ambiguous dates are flagged.
- Re-uploading a file without IDs duplicated records, and distinct files under one source could drop rows; identities are now deterministic content fingerprints.
- Contradicting sources were silently counted as duplicates; both versions are now preserved in `source_conflicts`.
- Every Risk Alert displayed REVIEW; real levels are shown.
- Risk window used wall-clock time, so historical datasets always returned insufficient information; `as_of` is supported for investigators.
- Graph loaded the 500 newest records globally; traversal is now anchored to the traced account.
- Event Hubs fallback IDs collided across partitions.
- Android release builds allowed cleartext HTTP.

## Verify before your demo
- `cd backend && pytest -q tests` — 20 tests, including the book's case studies 71–74 and 76.
- `python scripts/generate_case_study_data.py`, then ingest `data/samples/case_studies/*.csv` and trace `tp.a.collect@tracepay`.
- `docker compose up --build` against PostgreSQL, and build both mobile apps in Xcode and Android Studio. The Swift and Kotlin changes and the FastAPI routes could not be compiled or run in the environment that produced this release.

## Known limitations
- Live updates use an in-process WebSocket hub; the Azure template stays at one replica until Redis pub/sub fan-out is added.
- Mobile sessions expire after 20 minutes with no refresh token.
- Schema changes use startup `ALTER TABLE` statements; move to Alembic before production.
- The folder name `TracePay_2.0.0` is kept on purpose: Docker Compose names your database volumes after it.
