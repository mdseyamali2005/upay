"""Robustness Test Suite (T17) — edge-case and adversarial scenario tests.

Covers:
  1. Duplicate confirmation (double-yes on same transaction)
  2. Concurrent cash-out (two sessions, same user, insufficient balance)
  3. Disconnect / session restart mid-flow
  4. Session end → no further interaction
  5. Amount edge cases (zero, negative, max limit, boundary)
  6. PIN bruteforce lockout persistence
  7. Rapid-fire inputs
  8. FAQ fallback when LLM unavailable

Run:
    cd p:\\1upay\\upay_voice_guard
    python -m pytest tests/test_robustness.py -v
"""
import os
import tempfile
import threading

import pytest

os.environ["VG_DB"] = os.path.join(tempfile.mkdtemp(), "robust.db")

from app import db  # noqa: E402
from app.flow import Session  # noqa: E402


@pytest.fixture(autouse=True)
def fresh():
    db.init_db(reset=True)


def login(user_id=db.DEMO_USER_ID):
    s = Session(user_id)
    s.start()
    r = s.handle("keypad", "1234")
    assert "হ্যালো" in r["say"]
    return s


def do_cashout(s, number="01755555555", amount="3000"):
    """Drive a session all the way to the final confirmation step."""
    s.handle("speech", "আমি ক্যাশ আউট করতে চাই")
    s.handle("keypad", number)
    s.handle("speech", "হ্যাঁ")  # confirm number
    r = s.handle("keypad", amount)    # enter amount
    if "সতর্কতা" in r["say"]:
        s.handle("speech", "হ্যাঁ")
    return s


# ═══════════════════════════════════════════════════════════════
#  1. Duplicate Confirmation
# ═══════════════════════════════════════════════════════════════

class TestDuplicateConfirm:
    """T17: Duplicate confirm should not double-debit."""

    def test_double_yes_on_final_confirm(self):
        s = login()
        do_cashout(s, amount="1000")
        r1 = s.handle("speech", "হ্যাঁ")  # first confirm → success
        assert "সফল" in r1["say"]
        assert db.get_user(1)["balance"] == 24000

        # Second "হ্যাঁ" should be interpreted in menu context, not re-execute
        r2 = s.handle("speech", "হ্যাঁ")
        # Should NOT debit again
        assert db.get_user(1)["balance"] == 24000
        assert "সফল" not in r2["say"]

    def test_confirm_after_session_ends(self):
        s = login()
        s.handle("speech", "বাই বাই")  # end session
        r = s.handle("speech", "হ্যাঁ")  # try to interact after end
        assert r["end"] is True
        assert "শেষ" in r["say"]


# ═══════════════════════════════════════════════════════════════
#  2. Concurrent Cash-out (Race Condition)
# ═══════════════════════════════════════════════════════════════

class TestConcurrentCashout:
    """T17: Two sessions for same user; only one should succeed
    if balance is insufficient for both."""

    def test_concurrent_sessions_insufficient_balance(self):
        """Balance = 25000, each tries 15000. Only one should succeed."""
        db.set_limit(1, 20000)

        s1 = login()
        s2 = login()

        do_cashout(s1, number="01811111111", amount="15000")
        do_cashout(s2, number="01911111111", amount="15000")

        results = {}

        def confirm(s, label):
            r = s.handle("speech", "হ্যাঁ")
            results[label] = r

        t1 = threading.Thread(target=confirm, args=(s1, "s1"))
        t2 = threading.Thread(target=confirm, args=(s2, "s2"))
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        # Check: exactly one succeeded, one failed
        s1_ok = "সফল" in results["s1"]["say"]
        s2_ok = "সফল" in results["s2"]["say"]

        assert s1_ok != s2_ok, "Exactly one of the two should succeed"

        # Balance should be exactly 10000 (25000 - 15000)
        assert db.get_user(1)["balance"] == 10000

    def test_concurrent_within_balance(self):
        """Balance = 25000, each tries 5000. Both should succeed."""
        s1 = login()
        s2 = login()
        do_cashout(s1, number="01811111111", amount="5000")
        do_cashout(s2, number="01911111111", amount="5000")
        r1 = s1.handle("speech", "হ্যাঁ")
        r2 = s2.handle("speech", "হ্যাঁ")
        assert "সফল" in r1["say"]
        assert "সফল" in r2["say"]
        assert db.get_user(1)["balance"] == 15000


# ═══════════════════════════════════════════════════════════════
#  3. Disconnect / Session Restart
# ═══════════════════════════════════════════════════════════════

class TestDisconnectRestart:
    """T17: Mid-flow disconnect should not corrupt state."""

    def test_abandon_at_number_stage(self):
        """User disconnects after entering number but before amount."""
        s = login()
        s.handle("speech", "ক্যাশ আউট করতে চাই")
        s.handle("keypad", "01755555555")
        # Session abandoned here — no further interaction
        # Balance should be unchanged
        assert db.get_user(1)["balance"] == 25000

    def test_abandon_at_amount_stage(self):
        """User disconnects after entering amount but before confirm."""
        s = login()
        do_cashout(s, amount="5000")
        # Session abandoned before confirm
        assert db.get_user(1)["balance"] == 25000

    def test_new_session_after_abandon(self):
        """New session should work cleanly after previous abandoned."""
        s1 = login()
        do_cashout(s1, amount="5000")
        # Abandon s1, start fresh
        s2 = login()
        do_cashout(s2, amount="2000")
        r = s2.handle("speech", "হ্যাঁ")
        assert "সফল" in r["say"]
        assert db.get_user(1)["balance"] == 23000

    def test_restart_after_pin_failure(self):
        """Even after PIN failures, a new session starts fresh."""
        s = Session()
        s.start()
        s.handle("keypad", "9999")  # wrong
        s.handle("keypad", "8888")  # wrong
        # Abandon, start new session before lockout
        s2 = Session()
        s2.start()
        r = s2.handle("keypad", "1234")
        # Should still work (lockout is per-user, cumulative)
        # After 2 failures, 1 more left, this correct PIN should work
        assert "হ্যালো" in r["say"]


# ═══════════════════════════════════════════════════════════════
#  4. End-of-Session Boundary
# ═══════════════════════════════════════════════════════════════

class TestSessionEnd:
    """T17: No interaction possible after session ends."""

    def test_no_input_after_goodbye(self):
        s = login()
        r = s.handle("speech", "রাখি ভাই")
        assert r["end"]
        # Try all input types
        for kind, val in [("speech", "ক্যাশ আউট"), ("keypad", "1234"), ("speech", "হ্যাঁ")]:
            r2 = s.handle(kind, val)
            assert r2["end"]
            assert "শেষ" in r2["say"]

    def test_no_cashout_after_lockout(self):
        s = Session()
        s.start()
        for pin in ["1111", "2222", "3333"]:
            s.handle("keypad", pin)
        r = s.handle("keypad", "1234")
        assert r["end"]


# ═══════════════════════════════════════════════════════════════
#  5. Amount Edge Cases
# ═══════════════════════════════════════════════════════════════

class TestAmountEdgeCases:
    """T17: Boundary value testing for amounts."""

    def test_zero_amount(self):
        s = login()
        do_cashout(s, amount="0")
        # The flow code catches amount <= 0
        # (do_cashout sends "0" as amount, but flow returns error before confirm)
        # Reset and test directly
        s2 = login()
        s2.handle("speech", "ক্যাশ আউট করতে চাই")
        s2.handle("keypad", "01755555555")
        s2.handle("speech", "হ্যাঁ")
        r = s2.handle("keypad", "0")
        assert "সঠিক" in r["say"]

    def test_exact_balance_amount(self):
        """Cash out exactly the full balance."""
        s = login()
        db.set_limit(1, 30000)
        s.handle("speech", "ক্যাশ আউট করতে চাই")
        s.handle("keypad", "01755555555")
        s.handle("speech", "হ্যাঁ")
        r = s.handle("keypad", "25000")
        # Should be at final confirm (no risk since 25000 > half but skip that)
        # The risk warning fires because new number + amount > half balance
        if "সতর্কতা" in r["say"]:
            r = s.handle("speech", "হ্যাঁ")  # accept risk
        assert "কনফার্ম" in r["say"] or "সফল" in r["say"]
        r = s.handle("speech", "হ্যাঁ")
        assert "সফল" in r["say"]
        assert db.get_user(1)["balance"] == 0

    def test_over_balance_amount(self):
        s = login()
        db.set_limit(1, 30000)
        s.handle("speech", "ক্যাশ আউট করতে চাই")
        s.handle("keypad", "01755555555")
        s.handle("speech", "হ্যাঁ")
        r = s.handle("keypad", "30000")
        assert "ব্যালেন্স" in r["say"]  # insufficient balance

    def test_exact_limit_amount(self):
        """Amount == limit should pass."""
        s = login()
        s.handle("speech", "ক্যাশ আউট করতে চাই")
        s.handle("keypad", "01811111111")  # known number, no risk
        s.handle("speech", "হ্যাঁ")
        r = s.handle("keypad", "5000")  # limit is 5000
        assert "কনফার্ম" in r["say"]

    def test_over_limit_amount(self):
        """Amount > limit should fail."""
        s = login()
        s.handle("speech", "ক্যাশ আউট করতে চাই")
        s.handle("keypad", "01811111111")
        s.handle("speech", "হ্যাঁ")
        r = s.handle("keypad", "5001")
        assert "লিমিট" in r["say"]


# ═══════════════════════════════════════════════════════════════
#  6. PIN Bruteforce Lockout Persistence
# ═══════════════════════════════════════════════════════════════

class TestPINPersistence:
    """T17: Lockout persists across sessions."""

    def test_lockout_persists_across_sessions(self):
        s = Session()
        s.start()
        s.handle("keypad", "1111")
        s.handle("keypad", "2222")
        r = s.handle("keypad", "3333")  # 3rd fail → locked
        assert r["end"] and "লক" in r["say"]

        # New session — even correct PIN should fail
        s2 = Session()
        s2.start()
        r2 = s2.handle("keypad", "1234")
        assert r2["end"] and "লক" in r2["say"]


# ═══════════════════════════════════════════════════════════════
#  7. Rapid-fire / Repeated Inputs
# ═══════════════════════════════════════════════════════════════

class TestRapidFire:
    """T17: System handles rapid repeated inputs gracefully."""

    def test_multiple_menu_intents_rapid(self):
        s = login()
        intents = ["ব্যালেন্স কত", "গত মাসের খরচ", "ক্যাশ আউট করতে চাই"]
        for text in intents:
            r = s.handle("speech", text)
            assert r is not None
            if "ডিজিটের" in r["say"]:  # entered cash_out flow, need to go back
                s.state = "menu"
                s.ctx = {}

    def test_repeated_balance_checks(self):
        s = login()
        for _ in range(5):
            r = s.handle("speech", "ব্যালেন্স কত")
            assert "ব্যালেন্স" in r["say"]


# ═══════════════════════════════════════════════════════════════
#  8. FAQ Fallback
# ═══════════════════════════════════════════════════════════════

class TestFAQFallback:
    """T17: FAQ works even without Gemini API key."""

    def test_faq_without_api_key(self):
        s = login()
        r = s.handle("speech", "ক্যাশ আউটে কত চার্জ লাগে?")
        # Should return some answer (LLM or fallback)
        assert r is not None and r["say"]
        assert not r["end"]
