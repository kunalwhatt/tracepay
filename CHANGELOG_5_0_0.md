# Trace.Pay 5.0.0: TraceFlow · TraceSense · TraceScore · TraceRank · TraceShield · TraceBench

## TraceFlow: follow money correctly (`backend/app/traceflow.py`)
- **Time-respecting tracing**: a hop only counts if it happened after the money arrived. The graph shows
  "naive N links → time-respecting M" and can fade the impossible ones.
- **Attribution** by FIFO, LIFO and proportional methods, with the disagreement between them reported as uncertainty.
- **Bottlenecks** (node-capacitated max-flow / min-cut), **hold priority list**, **cash-out exits**
  (ATM, crypto, gift cards, betting), **golden-hour countdown** and **peel-chain** detection.
- Graph Analysis: "Follow this money" on any transfer; amber animated lines show where it went.

## TraceSense + TraceScore (`backend/app/tracesense.py`)
- TraceSense Core (the original three rules, renamed) plus TraceSense Deep signals: pass-through, dwell time,
  large relays, delay-proof high forwarding, collect-then-forward motifs, structuring / smurfing, round-trips,
  victim convergence (first-time payers), escalation (task scams), scam-typical amounts, mule lifecycle,
  coordinated mules (shared payers), k-core, bridges (Brandes betweenness), rings (Louvain), anomaly score
  (isolation forest) and a shop-like "regular customers" signal that lowers the score.
- TraceScore 0–100 with bands (Low, Watch, Review, High review), per-signal points, confidence and
  "what would change it" counterfactuals. Shown with an animated gauge in Account Analysis.

## TraceRank (`backend/app/tracerank.py`)
- Complaint intake (matched to recorded payments; starts a TraceFlow trace with golden hour and holds).
- Investigator labels (confirmed fraud / not suspicious / watch) with undo, all audited.
- Personalised PageRank suspicion propagation with explaining money paths; cleared accounts stop the spread.

## TraceShield (API)
- The payer's risk check now returns TraceShield reasons: first-time payee, unusual amount versus the payer's
  usual payments, new account, many first-time payers, high TraceScore, complaints, investigator flags.
  Mobile screens for these warnings come in the next delivery.

## TraceBench (`backend/app/tracebench.py`)
- Synthetic fraud world with ground truth (normal users, shops, mule rings with task-scam escalation),
  detector comparison (precision, recall, F1, false alarms, minutes to flag), robustness curves (mule delay)
  and data-gap experiments (records deleted). Runs live in the console in about 2 seconds.
- Default world: TraceScore 90% precision / 100% recall with 3 false alarms versus TraceSense Core 72% / 100%
  with 11; when mules wait 45–90 minutes TraceScore keeps 100% recall while Core falls to 14%.
  Synthetic data shows relative strength, not real-world accuracy.

## Other
- New console pages: TraceRank and TraceBench. "Payer Simulator" is now "Payment Check".
- "Pilot", "simulation" and "sandbox" wording removed from console screens and explanations.
- New tables `complaints` and `account_labels` are created automatically on start-up.
- 35 backend tests pass, including the real Pranay day (4 Oct) as the reference case.
