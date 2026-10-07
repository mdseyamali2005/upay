import os
import tempfile

import pytest

os.environ["VG_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from app import db  # noqa: E402
from app.flow import Session  # noqa: E402
from app.nlu import normalize_digits, parse_intent, spell_digits, yes_no  # noqa: E402


@pytest.fixture(autouse=True)
def fresh():
    db.init_db(reset=True)


def login():
    s = Session()
    s.start()
    r = s.handle("keypad", "1234")
    assert "হ্যালো" in r["say"]
    return s


def to_amount(s, number="01811111111"):
    s.handle("speech", "আমি ক্যাশ আউট করতে চাই")
    s.handle("keypad", number)
    return s.handle("speech", "হ্যাঁ ঠিক আছে")


def test_happy_path_and_balance():
    s = login()
    r = to_amount(s)
    assert r["expect"] == "keypad"
    r = s.handle("keypad", "3000")           # 3000 <= limit 5000, not > half of 25000
    assert "কনফার্ম" in r["say"]
    r = s.handle("speech", "হ্যাঁ")
    assert "সফল" in r["say"]
    assert db.get_user(1)["balance"] == 22000


def test_limit_blocks_and_cancels():
    s = login()
    to_amount(s)
    r = s.handle("keypad", "8000")
    assert "লিমিট" in r["say"] and r["expect"] == "keypad"
    r = s.handle("keypad", "9000")           # second violation cancels
    assert "ক্যানসেল" in r["say"]
    assert db.get_user(1)["balance"] == 25000


def test_limit_changed_on_website_mid_call():
    s = login()
    to_amount(s)
    db.set_limit(1, 1000)
    r = s.handle("keypad", "3000")
    assert "লিমিট" in r["say"]


def test_backend_rechecks_limit_at_execution():
    s = login()
    to_amount(s)
    r = s.handle("keypad", "3000")
    if "সতর্কতা" in r["say"]:
        r = s.handle("speech", "হ্যাঁ")
    db.set_limit(1, 1000)                    # lowered after the amount was accepted
    r = s.handle("speech", "হ্যাঁ")
    assert "হয়নি" in r["say"]
    assert db.get_user(1)["balance"] == 25000


def test_secrets_never_accepted_by_voice():
    s = Session()
    s.start()
    r = s.handle("speech", "এক দুই তিন চার")
    assert r["expect"] == "keypad" and "মুখে বলবেন না" in r["say"]
    s = login()
    s.handle("speech", "ক্যাশ আউট")
    r = s.handle("speech", "০১৭৫৫৫৫৫৫৫৫")
    assert r["expect"] == "keypad"


def test_pin_lockout():
    s = Session()
    s.start()
    s.handle("keypad", "1111")
    s.handle("keypad", "2222")
    r = s.handle("keypad", "3333")
    assert r["end"] and "লক" in r["say"]
    assert db.get_user(1)["locked"] == 1
    s2 = Session()
    s2.start()
    r = s2.handle("keypad", "1234")          # even the right PIN is refused once locked
    assert r["end"] and "লক" in r["say"]


def test_bad_numbers():
    for bad, msg in [("0171234", "১১ ডিজিটের"), ("02712345678", "০১৩"), ("01307339929", "নিজের নম্বরে")]:
        s = login()
        s.handle("speech", "ক্যাশ আউট করতে চাই")
        assert msg in s.handle("keypad", bad)["say"]
    # three bad tries in a row cancel the transaction
    s = login()
    s.handle("speech", "ক্যাশ আউট করতে চাই")
    s.handle("keypad", "1")
    s.handle("keypad", "2")
    assert "ক্যানসেল" in s.handle("keypad", "3")["say"]


def test_wrong_number_readback_then_retry():
    s = login()
    s.handle("speech", "ক্যাশ আউট")
    s.handle("keypad", "01755555555")
    r = s.handle("speech", "না ঠিক নাই")
    assert r["expect"] == "keypad" and "১১ ডিজিটের" in r["say"]


def test_risk_warning_for_new_number_over_half_balance():
    s = login()
    db.set_limit(1, 20000)
    to_amount(s)
    r = s.handle("keypad", "15000")
    assert "সতর্কতা" in r["say"]
    r = s.handle("speech", "না")
    assert "ক্যানসেল" in r["say"]
    assert db.get_user(1)["balance"] == 25000


def test_known_number_skips_risk():
    s = login()
    db.set_limit(1, 20000)
    to_amount(s, "01811111111")
    r = s.handle("keypad", "5000")  # 5000 is under 50% balance, only triggers abnormal amount (0.25)
    assert "সতর্কতা" not in r["say"]


def test_spending_matches_sql():
    import datetime as dt
    t = dt.date.today()
    y, m = (t.year - 1, 12) if t.month == 1 else (t.year, t.month - 1)
    total, _ = db.spending_summary(1, y, m)
    assert total > 0
    s = login()
    r = s.handle("speech", "গত মাসে মোট কত টাকা খরচ হয়েছে")
    assert str(total) in r["say"]


def test_keypad_yes_no_fallback():
    s = login()
    s.handle("speech", "ক্যাশ আউট")
    s.handle("keypad", "01755555555")
    assert s.handle("keypad", "1")["expect"] == "keypad"   # 1 = yes -> amount


def test_nlu_helpers():
    assert yes_no("ঠিক নাই") is False and yes_no("হ্যাঁ ঠিক আছে") is True and yes_no("আচ্ছা") is None
    assert normalize_digits("০১৭১-২৩৪ ৫৬৭৮") == "01712345678"
    assert parse_intent("আমি ক্যাশ আউট করতে চাই")["intent"] == "cash_out"
    assert parse_intent("গত মাসে কত খরচ")["intent"] == "spending"
    assert parse_intent("ব্যালেন্স কত")["intent"] == "balance"
    assert parse_intent("আমি টাকা পাঠাতে চাই")["intent"] == "send_money"


def test_send_money_not_yet():
    s = login()
    r = s.handle("speech", "আমি টাকা পাঠাতে চাই")
    assert "জলদি" in r["say"]
    assert not r["end"]


def test_fails_counter_resets_after_menu():
    """After a successful cash-out and return to menu, the
    unrecognized-intent counter should be back to zero."""
    s = login()
    # two unrecognized intents
    s.handle("speech", "abc xyz")
    s.handle("speech", "def uvw")
    # do a successful cash-out
    to_amount(s)
    s.handle("keypad", "3000")
    s.handle("speech", "হ্যাঁ")
    # now two more unrecognized intents should NOT trigger the lockout
    r = s.handle("speech", "abc xyz")
    assert not r["end"]
    r = s.handle("speech", "def uvw")
    assert not r["end"]
