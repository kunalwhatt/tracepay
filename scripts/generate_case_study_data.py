#!/usr/bin/env python3
"""Generate synthetic, clearly fictional datasets for the Trace.Pay case studies (book sections 71-75).

Every identifier is invented. The files exist so the graph, risk and ingestion behaviour can be
demonstrated and evaluated against a known ground truth. Re-running produces identical files.

    python scripts/generate_case_study_data.py [--date 2026-10-03]
"""
import argparse
import csv
import random
from datetime import datetime, timedelta
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "samples" / "case_studies"
HEADER = ["Txn Ref", "Sender Account", "Beneficiary", "Txn Amount", "Txn Date", "CCY"]


def write(name, rows):
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / name, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(HEADER)
        w.writerows(rows)
    print(f"wrote {name}: {len(rows)} rows")


def stamp(base, minutes, iso=False):
    # Cases 72-75 use the day-first Indian format on purpose, to exercise the date parser and its
    # ambiguity flag. Case 71 uses ISO timestamps so its records ingest as plain "observed".
    return (base + timedelta(minutes=minutes)).strftime("%Y-%m-%d %H:%M" if iso else "%d/%m/%Y %H:%M")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default="2026-10-03", help="day the scenario happens (YYYY-MM-DD)")
    day = datetime.fromisoformat(parser.parse_args().date)
    rng = random.Random(71)

    # Case 71: mule-like convergence, rapid fan-out, second and third hops.
    base = day.replace(hour=9, minute=41)
    rows = [["CS71-0001", "victim.v1@okhdfc", "tp.a.collect@tracepay", "25,000.00", stamp(base, 0, True), "INR"]]
    feeders = ["victim.v2@okaxis", "victim.v3@oksbi", "victim.v4@ybl", "victim.v5@okicici", "victim.v6@paytm", "victim.v7@okhdfc"]
    for i, sender in enumerate(feeders):
        rows.append([f"CS71-{i + 2:04d}", sender, "tp.a.collect@tracepay", f"{rng.randint(38, 92) * 100:,}.00", stamp(base, 3 + i * 4, True), "INR"])
    hops = [("tp.a.collect@tracepay", "tp.b.layer@tracepay", 52000, 12), ("tp.a.collect@tracepay", "tp.c.layer@tracepay", 41000, 15),
            ("tp.a.collect@tracepay", "tp.d.layer@tracepay", 36500, 19), ("tp.b.layer@tracepay", "tp.e.cashout@tracepay", 30000, 44),
            ("tp.b.layer@tracepay", "tp.f.cashout@tracepay", 19500, 51), ("tp.c.layer@tracepay", "tp.e.cashout@tracepay", 38000, 63),
            ("tp.d.layer@tracepay", "tp.g.merchant@tracepay", 12000, 90), ("tp.e.cashout@tracepay", "atm.withdrawal.hyd@bank", 60000, 140)]
    for i, (s, r, amt, m) in enumerate(hops):
        rows.append([f"CS71-{i + 8:04d}", s, r, f"{amt:,}.00", stamp(base, m, True), "INR"])
    write("71_mule_like_network.csv", rows)

    # Case 72: legitimate high-volume merchant (expected false-positive candidate).
    # Thirteen days of ordinary baseline trade, then a busy festival day that trips the breadth rule.
    rows, n = [], 0
    for back in range(13, -1, -1):
        open_at = (day - timedelta(days=back)).replace(hour=7, minute=30)
        customers = 42 if back == 0 else rng.randint(6, 14)
        for c in range(customers):
            n += 1
            rows.append([f"CS72-{n:04d}", f"customer{rng.randint(1, 90):02d}@okaxis", "chai.point.madhapur@tracepay",
                         f"{rng.choice([20, 30, 40, 60, 120, 180])}.00", stamp(open_at, int(c * (780 / customers))), "INR"])
    base = day.replace(hour=8, minute=0)
    rows += [[f"CS72-S{i + 1:03d}", "chai.point.madhapur@tracepay", supplier, f"{amt:,}.00", stamp(base, 600 + i * 45), "INR"]
             for i, (supplier, amt) in enumerate([("milk.supplier@okhdfc", 1800), ("tea.leaves.wholesale@ybl", 2400),
                                                  ("sugar.traders@oksbi", 900), ("rent.landlord@okicici", 3000)])]
    write("72_legitimate_merchant.csv", rows)

    # Case 73: missing middle hop (no file covers 11:45-13:00).
    base = day.replace(hour=11, minute=30)
    write("73_missing_middle_hop.csv", [
        ["CS73-0001", "victim.v2@okaxis", "tp.x.holding@tracepay", "18,000.00", stamp(base, 0), "INR"],
        ["CS73-0002", "tp.x.holding@tracepay", "tp.y.unknown@tracepay", "10,000.00", stamp(base, 102), "INR"],
    ])

    # Case 75: two sources disagree about TX-900.
    base = day.replace(hour=11, minute=20)
    write("75_source_a.csv", [["CS75-TX-900", "acct.a@tracepay", "acct.b@tracepay", "5,000.00", stamp(base, 0), "INR"]])
    write("75_source_b.csv", [["CS75-TX-900", "acct.a@tracepay", "acct.c@tracepay", "5,000.00", stamp(base, 0), "INR"]])


if __name__ == "__main__":
    main()
