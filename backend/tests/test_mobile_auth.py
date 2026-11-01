"""Sign-up and sign-in with a mobile number or email, no OTP."""
from pydantic import ValidationError
from app.schemas import RegisterIn, LoginIn, normalize_mobile


def test_mobile_normalisation():
    assert normalize_mobile("+91 98480-12345") == "9848012345"
    assert normalize_mobile("919848012345") == "9848012345"
    for bad in ["12345", "5848012345", "98480 1234"]:
        try:
            normalize_mobile(bad); raise AssertionError(bad)
        except ValueError:
            pass


def test_register_needs_email_or_mobile():
    assert RegisterIn(mobile="98480 12345", password="Supersecret#12").mobile == "9848012345"
    assert RegisterIn(email="a@b.co", password="Supersecret#12").email == "a@b.co"
    try:
        RegisterIn(password="Supersecret#12"); raise AssertionError("accepted")
    except ValidationError:
        pass


def test_login_accepts_identifier_or_legacy_email():
    assert LoginIn(identifier="9848012345", password="x").identifier == "9848012345"
    assert LoginIn(email="a@b.co", password="x").email == "a@b.co"
