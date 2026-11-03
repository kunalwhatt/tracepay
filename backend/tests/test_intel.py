"""Fraud intelligence: scam messages, links, name mismatch, lifecycle, cooling-off, reputation, campaigns."""
from datetime import datetime, timedelta, timezone
from app import intel


def test_scam_message_scores_high_and_extracts():
    m = intel.analyze_text("URGENT: Your SBI KYC is pending, account will be blocked within 24 hours. "
                           "Click https://sbi-kyc-update.xyz/verify and pay ₹10 to verify@ybl. Call 9876543210")
    assert m["score"] >= 75 and m["upi_ids"] == ["verify@ybl"] and m["phones"] == ["9876543210"]
    assert intel.analyze_text("Dinner at 8? Pay me 200 at ravi@okaxis")["score"] == 0


def test_links():
    assert intel.analyze_link("http://sbi-kyc-update.xyz/app.apk")["score"] >= 75
    assert intel.analyze_link("https://www.onlinesbi.sbi/")["score"] == 0


def test_name_mismatch_and_stage():
    assert intel.name_mismatch("ABC Electronics", "Ramesh Kumar")["code"] == "NAME_MISMATCH"
    assert intel.name_mismatch("Ramesh Stores", "Ramesh Kumar") is None
    now = datetime.now(timezone.utc)
    assert intel.lifecycle_stage(12, now - timedelta(days=3), now, set())["stage"] == "recruited"
    assert intel.lifecycle_stage(9, now - timedelta(days=90), now, {"PASS_THROUGH"})["stage"] == "active_mule"


def test_cooling_reputation_campaigns():
    assert intel.cooling_seconds(80, "high_review", False, 100) == 600 and intel.cooling_seconds(10, "low", False, 100) == 0
    assert intel.reporter_weight(0, 3, 3) == 0.2 and intel.reporter_weight(4, 0, 4) == 1.0
    rs = [{"id": 1, "target_ref": "a@ybl", "category": "task_scam", "description": "like videos earn money telegram", "amount": "500", "created_at": "1"},
          {"id": 2, "target_ref": "b@ybl", "category": "task_scam", "description": "telegram like videos earn money", "amount": "900", "created_at": "2"}]
    c = intel.campaigns(rs)
    assert c and c[0]["size"] == 2 and c[0]["total_lost"] == 1400.0
