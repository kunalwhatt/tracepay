"""Schema agent tests with real-world layouts (no database, Gemini disabled)."""
import os
os.environ.pop("GEMINI_API_KEY", None)

from app.schema_agent import build_plan, extract_counterparty, load_sheets, normalize_with_plan, plan_from_request, signed_amount

HDFC = """HDFC BANK Ltd.,,,,,,
Account Statement,,,,,,
Account No :50100123456789,,,,,,
Customer: RAVI KUMAR,,,,,,
Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
01/10/26,UPI-SURESH TRADERS-suresh.traders@okaxis-HDFC0001-427512345678-PAYMENT,0000427512345678,01/10/26,"2,500.00",,"47,500.00"
01/10/26,UPI/427599990000/ANITA SHARMA/SBIN0000123/Collect,0000427599990000,01/10/26,,"12,000.00","59,500.00"
02/10/26,ATM WDL/HYD MADHAPUR,,02/10/26,"5,000.00",,"54,500.00"
,,,,,,
,Closing balance,,,,,"54,500.00"
"""

SBI = """Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance
03 Oct 2026,03 Oct 2026,TO TRANSFER-UPI/DR/427611112222/MEERA I/YESB/meera.iyer@tracepay/Paid,427611112222,800.00,,9200.00
03 Oct 2026,03 Oct 2026,BY TRANSFER-NEFT*HDFC0000001*N2760*ACME PAYROLL,N2760,,45000.00,54200.00
"""

PHONEPE = """Date,Transaction Details,Type,Amount
"Oct 03, 2026 09:41 am",Paid to Chai Point,DEBIT,₹120
"Oct 03, 2026 10:05 am",Received from rohan.shah@ybl,CREDIT,"₹1,500"
"""

ODD_TRANSFERS = """Payer VPA,Payee VPA,Amt (₹),Txn Date,Txn Time,UTR
victim.one@okhdfc,collector@tracepay,"25,000",03-10-2026,09:41:00,UTR001
collector@tracepay,layer.b@tracepay,"12,000.50",03-10-2026,09:53:30,UTR002
"""

UNKNOWN = """From,To,Value,When
a@x,b@y,10,2026-10-03
"""


def plan_for(text, name="file.csv", account=""):
    sheets = load_sheets(name, text.encode())
    sheet, info = next(iter(sheets.items()))
    return sheet, info, build_plan(sheet, info, name, use_gemini=False, statement_account=account)


def rows(sheet, info, plan):
    out, occ = [], {}
    for i, (_, r) in enumerate(info["frame"].iterrows()):
        try:
            n = normalize_with_plan(r.to_dict(), plan, info["header_row"] + 2 + i, sheet, occ)
        except ValueError as exc:
            out.append(("error", str(exc))); continue
        out.append(n)
    return out


def test_hdfc_statement_with_preamble():
    sheet, info, plan = plan_for(HDFC, "hdfc_statement.csv")
    assert info["header_row"] == 4
    assert plan["mode"] == "statement" and plan["ready"]
    assert plan["mapping"]["debit_amount"] == "Withdrawal Amt." and plan["mapping"]["credit_amount"] == "Deposit Amt."
    assert plan["mapping"]["transaction_id"] == "Chq./Ref.No."
    assert "Closing Balance" not in plan["mapping"].values()
    assert plan["statement_account"] == "acct:50100123456789" and plan["statement_account_source"] == "file"
    result = rows(sheet, info, plan)
    real = [r for r in result if r is not None]
    assert len(real) == 3  # blank row and the closing-balance footer are skipped
    paid, received, atm = real
    assert (paid.sender_id, paid.receiver_id, str(paid.amount)) == ("acct:50100123456789", "suresh.traders@okaxis", "2500.00")
    assert (received.sender_id, received.receiver_id) == ("name:anita.sharma", "acct:50100123456789")
    assert atm.receiver_id == "cash:atm-withdrawal"
    from zoneinfo import ZoneInfo
    local = paid.timestamp.astimezone(ZoneInfo('Asia/Kolkata'))
    assert (local.day, local.month, local.hour) == (1, 10, 0)  # 01/10/26 read as DD/MM, midnight IST
    assert any("date only" in r for r in paid.repairs)


def test_sbi_statement_needs_owner_then_works():
    sheet, info, plan = plan_for(SBI, "sbi.csv")
    assert plan["mode"] == "statement" and not plan["ready"]
    assert any("statement account" in m for m in plan["missing"])
    plan = plan_from_request({"statement_account": "Kunal@TracePay"}, list(info["frame"].columns), plan)
    assert plan["ready"]
    out = rows(sheet, info, plan)
    assert out[0].receiver_id == "meera.iyer@tracepay" and out[0].sender_id == "kunal@tracepay"
    assert out[1].sender_id == "name:acme.payroll" and str(out[1].amount) == "45000.00"


def test_upi_app_export_with_debit_credit_marker():
    sheet, info, plan = plan_for(PHONEPE, "phonepe.csv", account="kunal@tracepay")
    assert plan["mode"] == "statement" and plan["mapping"]["direction"] == "Type" and plan["ready"]
    out = rows(sheet, info, plan)
    assert out[0].sender_id == "kunal@tracepay" and out[0].receiver_id.startswith("name:") and "chai" in out[0].receiver_id
    assert out[1].sender_id == "rohan.shah@ybl" and str(out[1].amount) == "1500.00"
    assert out[0].timestamp.hour == 4 and out[0].timestamp.minute == 11  # 09:41 IST


def test_transfer_file_with_odd_headers_and_split_date_time():
    sheet, info, plan = plan_for(ODD_TRANSFERS, "case_file.csv")
    assert plan["mode"] == "transfers" and plan["ready"]
    assert plan["mapping"]["date"] == "Txn Date" and plan["mapping"]["time"] == "Txn Time"
    out = rows(sheet, info, plan)
    assert out[1].transaction_id == "UTR002" and str(out[1].amount) == "12000.50"
    assert (out[1].timestamp.hour, out[1].timestamp.minute) == (4, 23)


def test_unrecognised_layout_reports_what_is_missing():
    sheet, info, plan = plan_for(UNKNOWN, "mystery.csv")
    assert not plan["ready"] and any("timestamp" in m for m in plan["missing"])
    fixed = plan_from_request({"mapping": {**plan["mapping"], "timestamp": "When", "amount": "Value"}}, list(info["frame"].columns), plan)
    assert fixed["ready"] and fixed["source"]["timestamp"] == "you"


def test_amount_and_counterparty_parsing():
    assert signed_amount("1,250.00 Dr") == (signed_amount("1250")[0], -1)
    assert signed_amount("(300)")[1] == -1 and signed_amount("-")[0] is None
    assert extract_counterparty("NEFT CHARGES INCL GST")[0] == "bank:charges"
    assert extract_counterparty("UPI/427/ravi@okaxis/x", own="me@tracepay")[0] == "ravi@okaxis"
