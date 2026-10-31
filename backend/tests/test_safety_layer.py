"""UPI QR parsing and the community-adjusted safety verdict."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from app.ids import parse_upi
from app import community


def test_parse_gpay_phonepe_paytm_qr():
    q = parse_upi("upi://pay?pa=Shop.Owner@okaxis&pn=Ravi%20Stores&am=250.5&tn=Tea&mc=5411&tr=ORD123&cu=INR")
    assert q["vpa"] == "shop.owner@okaxis" and q["name"] == "Ravi Stores" and q["amount"] == "250.5"
    assert q["merchant_code"] == "5411" and q["txn_ref"] == "ORD123" and not q["is_tracepay"]
    assert parse_upi("PRANAY.KUNTA@tracepay")["is_tracepay"]
    assert parse_upi("hello world")["vpa"] is None and parse_upi("upi://pay?pn=NoId")["vpa"] is None


def test_verdict_combines_behaviour_community_and_trust():
    now = datetime.now(timezone.utc)
    reports = [SimpleNamespace(status="verified", category="task_scam", created_at=now - timedelta(days=2)),
               SimpleNamespace(status="pending", category="scam_payment", created_at=now - timedelta(days=5)),
               SimpleNamespace(status="rejected", category="other", created_at=now)]
    extra = community.community_factors(reports, complaints=1, label=None, merchant=None, now=now)
    codes = {f["code"] for f in extra}
    assert codes == {"VERIFIED_REPORTS", "COMMUNITY_REPORTS", "COMPLAINTS"}
    trace = {"score": 30, "contributions": [{"code": "PASS_THROUGH", "label": "Money passes straight through", "points": 30, "detail": "x"}]}
    out = community.combine(trace, extra)
    assert out["score"] == 81 and out["band"] == "high_review"  # 30 behaviour + 20 confirmed + 16 reports + 15 complaint and out["factors"][0]["points"] >= out["factors"][-1]["points"]


def test_verified_shop_lowers_score_and_ids_are_masked():
    extra = community.community_factors([], 0, None, {"verified": True, "display_name": "Chai Corner", "category": "Food"})
    out = community.combine({"score": 18, "contributions": [{"code": "INBOUND_BREADTH", "label": "Many senders", "points": 18}]}, extra)
    assert out["score"] == 0 and out["band"] == "low"
    assert community.mask("paid kunal.test@tracepay twice") == "paid ku***@tracepay twice"
    assert community.combine({"score": None, "contributions": []}, [])["band"] == "insufficient_information"
