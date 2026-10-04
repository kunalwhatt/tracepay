# Trace.Pay 4.5.0: ingestion agent, assistant, real reports, payments fixed

## Payments work again
- "Pilot safety service is temporarily unavailable" is fixed. The transfer rate limit (20 per minute per user)
  uses Redis when present and an in-process counter otherwise, instead of refusing every payment.

## Ingestion accepts real datasets
- New schema agent (`backend/app/schema_agent.py`) understands two shapes:
  - **Transfers**: sender/receiver files with any common naming (payer VPA, payee, beneficiary, UTR, RRN ...),
    including separate date and time columns and name-only parties.
  - **Bank / UPI statements**: finds the header below preamble rows, reads withdrawal/deposit columns, Dr/Cr markers
    or signed amounts, ignores balance columns, skips opening/closing/summary rows, reads the statement owner from the
    file header when present, and derives counterparties from narrations (UPI IDs, names, ATM, interest, charges).
- **Gemini as an agent**: when the rules cannot place a column, Gemini proposes column roles and the dataset type.
  It never supplies values; suggestions are validated against the file. Models fall back automatically
  (GEMINI_MODEL, then gemini-flash-latest, then gemini-2.5-flash) and errors are shown instead of hidden.
  The old code asked Gemini for a schema feature it does not support, so AI mapping silently never worked.
- New `POST /api/v1/ingestion/preview` returns the plan and a normalised preview without saving.
  `POST /api/v1/ingestion/file` accepts the reviewed plan and returns real stage timings.
- `GET /api/v1/system/gemini` checks the Gemini key with a live request.

## Web console
- **Data Ingestion** rebuilt: drag and drop; "Behind the scenes" pipeline animated from real server stages
  (upload, read, detect, AI agent, plan, validate, deduplicate, save, archive); editable mapping with who chose
  each column (rule / AI / you); statement owner; live preview of the first rows; import result; import history.
- **Reset data** (admin): delete imported evidence, optionally with cases and reports, after typing RESET.
  Users, wallets, the TraceBank ledger and the audit log are always kept.
- **Assistant** ("Ask Trace.Pay" on every screen): Learn tab with diagrams and tables (hops, risk flagging,
  line colours, ingestion, statements, conflicts, ledger) and an Ask tab answered by Gemini from live data, with a
  built-in fallback. Help links on the graph, accounts and ingestion screens open the right topic.
- **Reports** are real: generated from persisted evidence (behaviour, rules-v1 evidence, network, every source
  record with file and row, TraceBank transfers, conflicts, limitations), optional labelled AI summary,
  Print / Save as PDF, CSV and JSON downloads, delete.
- **Cases** are functional: create with a linked account, change status, open the account or trace, attach reports.
- **Account Analysis**: plain-language summary, rule-by-rule table (threshold vs observed), money in vs out per day,
  time-of-day and transfer-size charts, counterparty table with "both ways" flags, record sources, Explain and
  Evidence report buttons.
- **User Management**: participants with live TraceBank balances and a Fund wallet button for admins.
- Duplicate page titles removed.

## Synced from your repo
Web API auto-detection, Dockerfile `public/` fix, Android JVM 17 + `setContent` import + Azure URL, iOS Azure URL
with safe fallback, Android APK workflow.

## Tests
27 backend tests pass, including statement layouts (HDFC-style with preamble, SBI-style, UPI app export),
transfer files with odd headers, and behaviour-profile checks.
