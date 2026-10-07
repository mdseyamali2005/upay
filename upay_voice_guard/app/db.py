"""Mock ledger (SQLite). ALL DATA IS FAKE. The per-transaction limit is
enforced here in SQL, not only in the conversation."""
import datetime as dt
import hashlib
import hmac
import os
import random
import sqlite3
from contextlib import contextmanager

DEMO_USER_ID = 1
DEMO_PIN = "1234"  # FAKE demo PIN. Never use a real one.
MAX_PIN_TRIES = 3


def _path():
    if "VG_DB" in os.environ:
        return os.environ["VG_DB"]
    if os.environ.get("VERCEL"):
        return "/tmp/voice_guard.db"
    return "voice_guard.db"


@contextmanager
def db():
    c = sqlite3.connect(_path())
    c.row_factory = sqlite3.Row
    try:
        yield c
        c.commit()
    finally:
        c.close()


def _hash(pin, salt_hex):
    return hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(salt_hex), 50_000).hex()


SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY, name TEXT, phone TEXT, pin_hash TEXT, salt TEXT,
  balance INTEGER, max_txn_limit INTEGER, failed_pin INTEGER DEFAULT 0, locked INTEGER DEFAULT 0,
  name_tts TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, ts TEXT,
  kind TEXT, counterparty TEXT, amount INTEGER);
CREATE TABLE IF NOT EXISTS known_numbers (
  user_id INTEGER, number TEXT, PRIMARY KEY (user_id, number));
CREATE TABLE IF NOT EXISTS contacts (
  user_id INTEGER, name TEXT, phone_number TEXT, PRIMARY KEY (user_id, phone_number));
"""


def _shift_month(y, m, delta):
    idx = y * 12 + (m - 1) + delta
    return idx // 12, idx % 12 + 1


def init_db(reset=False):
    if reset and os.path.exists(_path()):
        os.remove(_path())
    with db() as c:
        c.executescript(SCHEMA)
        # Ensure name_tts column exists (migration for older DBs)
        try:
            c.execute("ALTER TABLE users ADD COLUMN name_tts TEXT DEFAULT ''")
        except Exception:
            pass  # column already exists
        # Update user 1 info if exists or seed if empty
        r = c.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        if r == 0:
            _seed(c)
        else:
            salt = os.urandom(8).hex()
            c.execute("UPDATE users SET name=?, phone=?, pin_hash=?, salt=? WHERE id=?",
                      ("MD. SEYAM ALI", "01307339929", _hash(DEMO_PIN, salt), salt, DEMO_USER_ID))


def _seed(c):
    salt = os.urandom(8).hex()
    c.execute("INSERT INTO users VALUES (?,?,?,?,?,?,?,0,0,?)",
              (DEMO_USER_ID, "MD. SEYAM ALI", "01307339929", _hash(DEMO_PIN, salt), salt, 25000, 5000, ""))
    rnd = random.Random(42)
    today = dt.date.today()
    kinds = ["send_money", "mobile_recharge", "pay_bill", "cash_out"]
    for back in range(3):
        y, m = _shift_month(today.year, today.month, -back)
        n, max_day = (3, max(1, today.day)) if back == 0 else (10, 28)
        for _ in range(n):
            ts = dt.date(y, m, rnd.randint(1, max_day)).isoformat()
            who = "017" + "".join(str(rnd.randint(0, 9)) for _ in range(8))
            c.execute("INSERT INTO transactions (user_id, ts, kind, counterparty, amount) VALUES (?,?,?,?,?)",
                      (DEMO_USER_ID, ts, rnd.choice(kinds), who,
                       rnd.choice([100, 200, 300, 500, 750, 1000, 1500, 2000, 2500])))
        c.execute("INSERT INTO transactions (user_id, ts, kind, counterparty, amount) VALUES (?,?,?,?,?)",
                  (DEMO_USER_ID, dt.date(y, m, 1).isoformat(), "add_money", "bank", 5000))
    for n in ("01811111111", "01911111111"):
        c.execute("INSERT INTO known_numbers VALUES (?,?)", (DEMO_USER_ID, n))


def get_user(user_id):
    with db() as c:
        r = c.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return dict(r) if r else None


def check_pin(user_id, pin):
    """-> (status, tries_left); status in ok | wrong | locked"""
    with db() as c:
        u = c.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if u["locked"]:
            return "locked", 0
        if hmac.compare_digest(_hash(pin, u["salt"]), u["pin_hash"]):
            c.execute("UPDATE users SET failed_pin=0 WHERE id=?", (user_id,))
            return "ok", MAX_PIN_TRIES
        failed = u["failed_pin"] + 1
        locked = 1 if failed >= MAX_PIN_TRIES else 0
        c.execute("UPDATE users SET failed_pin=?, locked=? WHERE id=?", (failed, locked, user_id))
        return ("locked" if locked else "wrong"), MAX_PIN_TRIES - failed


def set_limit(user_id, limit):
    with db() as c:
        c.execute("UPDATE users SET max_txn_limit=? WHERE id=?", (int(limit), user_id))


def is_known(user_id, number):
    with db() as c:
        return c.execute("SELECT 1 FROM known_numbers WHERE user_id=? AND number=?",
                         (user_id, number)).fetchone() is not None


def cash_out(user_id, number, amount):
    """Atomic. Returns new balance, or None if balance/limit check fails."""
    with db() as c:
        cur = c.execute(
            "UPDATE users SET balance = balance - ? WHERE id=? AND balance >= ? AND ? <= max_txn_limit",
            (amount, user_id, amount, amount))
        if cur.rowcount != 1:
            return None
        c.execute("INSERT INTO transactions (user_id, ts, kind, counterparty, amount) VALUES (?,?,?,?,?)",
                  (user_id, dt.datetime.now().isoformat(), "cash_out", number, amount))
        c.execute("INSERT OR IGNORE INTO known_numbers VALUES (?,?)", (user_id, number))
        return c.execute("SELECT balance FROM users WHERE id=?", (user_id,)).fetchone()["balance"]


def get_contacts(user_id):
    with db() as c:
        rows = c.execute("SELECT name, phone_number FROM contacts WHERE user_id=? ORDER BY name", (user_id,)).fetchall()
        return [dict(r) for r in rows]


def add_contact(user_id, name, phone_number):
    with db() as c:
        c.execute("INSERT OR REPLACE INTO contacts (user_id, name, phone_number) VALUES (?, ?, ?)",
                  (user_id, name, phone_number))


def send_money(user_id, number, amount):
    """Atomic. Returns new balance, 'limit' if limit exceeded, 'cooldown' if sent in last 10 mins, or None if balance fails."""
    with db() as c:
        # Check cooldown (10 minutes)
        # ts is ISO format, e.g. 2026-10-07T11:02:00. We can do string comparison or python parse.
        # Let's fetch recent transactions for this number and check in python.
        recent = c.execute("SELECT ts FROM transactions WHERE user_id=? AND kind='send_money' AND counterparty=? ORDER BY id DESC LIMIT 1",
                           (user_id, number)).fetchone()
        if recent:
            try:
                last_ts = dt.datetime.fromisoformat(recent["ts"])
                if dt.datetime.now() - last_ts < dt.timedelta(minutes=10):
                    return 'cooldown'
            except ValueError:
                pass # If it's just a date without time, ignore cooldown

        cur = c.execute(
            "UPDATE users SET balance = balance - ? WHERE id=? AND balance >= ? AND ? <= max_txn_limit",
            (amount, user_id, amount, amount))
        if cur.rowcount != 1:
            # check if it was limit or balance
            user = c.execute("SELECT balance, max_txn_limit FROM users WHERE id=?", (user_id,)).fetchone()
            if amount > user["max_txn_limit"]:
                return 'limit'
            return None
        c.execute("INSERT INTO transactions (user_id, ts, kind, counterparty, amount) VALUES (?,?,?,?,?)",
                  (user_id, dt.datetime.now().isoformat(), "send_money", number, amount))
        c.execute("INSERT OR IGNORE INTO known_numbers VALUES (?,?)", (user_id, number))
        return c.execute("SELECT balance FROM users WHERE id=?", (user_id,)).fetchone()["balance"]


def spending_summary(user_id, year, month):
    """-> (total, (top_kind, top_amount) | None). Excludes add_money (incoming)."""
    prefix = f"{year:04d}-{month:02d}%"
    with db() as c:
        rows = c.execute(
            "SELECT kind, SUM(amount) AS s FROM transactions "
            "WHERE user_id=? AND ts LIKE ? AND kind != 'add_money' GROUP BY kind ORDER BY s DESC",
            (user_id, prefix)).fetchall()
    total = sum(r["s"] for r in rows)
    return total, ((rows[0]["kind"], rows[0]["s"]) if rows else None)


def get_transactions(user_id):
    """Return all transactions for a user, newest first."""
    with db() as c:
        rows = c.execute(
            "SELECT id, ts, kind, counterparty, amount FROM transactions "
            "WHERE user_id=? ORDER BY ts DESC, id DESC",
            (user_id,)).fetchall()
        return [dict(r) for r in rows]


def set_name_tts(user_id, name_tts):
    with db() as c:
        c.execute("UPDATE users SET name_tts=? WHERE id=?", (name_tts, user_id))


# ── T4: Personalized Risk Scoring ──

def get_risk_signals(user_id, number, amount):
    """Compute personalized behavioral risk signals for a transaction.

    Returns a dict with:
      - score: float 0.0 (safe) to 1.0 (high risk)
      - factors: list of human-readable risk factor strings (Bangla)
      - is_risky: bool (score >= threshold)
    """
    signals = []
    weights = []

    with db() as c:
        user = dict(c.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone())

        # ── Signal 1: Recipient Novelty ──
        is_new = c.execute(
            "SELECT 1 FROM known_numbers WHERE user_id=? AND number=?",
            (user_id, number)).fetchone() is None
        if is_new:
            signals.append("নতুন নম্বর — আগে কখনো এই নম্বরে লেনদেন হয়নি")
            weights.append(0.30)

        # ── Signal 2: Amount vs Historical Average ──
        rows = c.execute(
            "SELECT amount FROM transactions WHERE user_id=? AND kind='cash_out' "
            "ORDER BY id DESC LIMIT 20", (user_id,)).fetchall()
        past_amounts = [r["amount"] for r in rows]
        if past_amounts:
            avg = sum(past_amounts) / len(past_amounts)
            std = (sum((a - avg) ** 2 for a in past_amounts) / len(past_amounts)) ** 0.5
            if std > 0 and amount > avg + 2 * std:
                signals.append(
                    f"অস্বাভাবিক পরিমাণ — গড় {int(avg)} টাকার তুলনায় {amount} টাকা অনেক বেশি")
                weights.append(0.25)
            elif amount > avg * 3 and avg > 0:
                signals.append(
                    f"বড় অংক — গড় ক্যাশ আউট {int(avg)} টাকার তুলনায় ৩ গুণ বেশি")
                weights.append(0.20)
        else:
            # No history = slightly risky
            if amount > 2000:
                signals.append("প্রথমবার ক্যাশ আউট — কোনো পূর্ববর্তী লেনদেনের ইতিহাস নেই")
                weights.append(0.15)

        # ── Signal 3: Balance Ratio ──
        balance = user["balance"]
        if balance > 0:
            ratio = amount / balance
            if ratio > 0.8:
                signals.append(
                    f"ব্যালেন্সের {int(ratio * 100)}% — প্রায় সব টাকা তোলা হচ্ছে")
                weights.append(0.25)
            elif ratio > 0.5:
                signals.append(
                    f"ব্যালেন্সের {int(ratio * 100)}% — অর্ধেকের বেশি তোলা হচ্ছে")
                weights.append(0.15)

        # ── Signal 4: Frequency (multiple cash-outs today) ──
        today = dt.date.today().isoformat()
        today_count = c.execute(
            "SELECT COUNT(*) FROM transactions WHERE user_id=? AND kind='cash_out' AND ts=?",
            (user_id, today)).fetchone()[0]
        if today_count >= 3:
            signals.append(
                f"আজই {today_count} বার ক্যাশ আউট — অস্বাভাবিক ফ্রিকোয়েন্সি")
            weights.append(0.20)
        elif today_count >= 2:
            signals.append(
                f"আজই {today_count} বার ক্যাশ আউট হয়েছে")
            weights.append(0.10)

        # ── Signal 5: Rapid successive transactions (2+ in last hour is unusual) ──
        recent = c.execute(
            "SELECT COUNT(*) FROM transactions WHERE user_id=? AND kind='cash_out' "
            "AND ts=? ORDER BY id DESC LIMIT 5",
            (user_id, today)).fetchone()[0]
        if recent >= 2 and today_count >= 2:
            signals.append("অল্প সময়ে একাধিক ক্যাশ আউট")
            weights.append(0.10)

    # Compute overall risk score
    score = min(1.0, sum(weights)) if weights else 0.0

    # Risk threshold: 0.35 = moderate risk triggers warning
    RISK_THRESHOLD = 0.35
    return {
        "score": round(score, 2),
        "factors": signals,
        "is_risky": score >= RISK_THRESHOLD,
        "threshold": RISK_THRESHOLD,
    }
