"""Deterministic call-flow state machine.
Rule: sensitive values (PIN, number, amount) are accepted ONLY from the keypad.
Speech is used for intent, questions and yes/no. The LLM (later) may pick an
intent; it never moves money - this code does."""
import datetime as dt
import re

from . import db
from .nlu import normalize_digits, parse_intent, to_bn, yes_no
from .speech_utils import name_for_speech

PIN_LEN = 4
MAX_TRIES = 3
S_PIN, S_MENU, S_NUM, S_NUM_OK, S_AMT, S_RISK, S_FINAL, S_END = (
    "pin", "menu", "number", "number_ok", "amount", "risk", "final", "end")

MONTHS = ["জানুয়ারি", "ফেব্রুয়ারি", "মার্চ", "এপ্রিল", "মে", "জুন", "জুলাই",
          "আগস্ট", "সেপ্টেম্বর", "অক্টোবর", "নভেম্বর", "ডিসেম্বর"]
KINDS = {"send_money": "সেন্ড মানি", "mobile_recharge": "মোবাইল রিচার্জ",
         "pay_bill": "বিল পেমেন্ট", "cash_out": "ক্যাশ আউট"}
SECRET = "সিকিউরিটির জন্য এটা মুখে বলবেন না।"
YN_HINT = "'হ্যাঁ' বা 'না' বলুন।"


def reply(say, expect="speech", digits=None, end=False):
    return {"say": say, "expect": expect, "digits": digits, "end": end}


class Session:
    def __init__(self, user_id=db.DEMO_USER_ID):
        self.user_id = user_id
        self.state = S_PIN
        self.fails = 0
        self.ctx = {}

    # ---------- public ----------
    def start(self):
        return reply(f"আপনার {PIN_LEN} ডিজিটের পিন, কীপ্যাডে দিন।", "keypad", PIN_LEN)

    def handle(self, kind, value=""):
        value = (value or "").strip()
        if self.state == S_END:
            return reply("কলটি শেষ হয়েছে।", "none", end=True)
        return getattr(self, f"_on_{self.state}")(kind, value)

    # ---------- helpers ----------
    def _user(self):  # always re-read: the limit can change mid-call
        return db.get_user(self.user_id)

    def _menu(self, prefix=""):
        self.state, self.ctx, self.fails = S_MENU, {}, 0
        return reply(prefix + "আর কিছু করতে পারি?")

    def _end(self, msg):
        self.state = S_END
        return reply(msg, "none", end=True)

    def _ask_number(self, prefix=""):
        self.state = S_NUM
        return reply(prefix + "এজেন্টের ১১ ডিজিটের মোবাইল নম্বর, কীপ্যাডে দিন।", "keypad", 11)

    def _ask_amount(self, prefix=""):
        self.state = S_AMT
        action_text = "সেন্ড মানি" if self.ctx.get("action") == "send_money" else "ক্যাশ আউট"
        return reply(prefix + f"কত টাকা {action_text} করবেন? অ্যামাউন্ট কীপ্যাডে দিন।", "keypad")

    def _cancel(self, why):
        return self._menu(f"{why}, ট্রানজেকশন ক্যানসেল করা হয়েছে। ")

    def _need_keypad(self, digits=None):
        return reply(f"{SECRET} কীপ্যাডে টাইপ করুন।", "keypad", digits)

    # ---------- states ----------
    def _on_pin(self, kind, value):
        if kind != "keypad":
            return reply(f"{SECRET} আপনার পিন কীপ্যাডে দিন।", "keypad", PIN_LEN)
        pin = normalize_digits(value)
        if len(pin) != PIN_LEN:
            return reply(f"পিন {PIN_LEN} ডিজিটের হতে হবে। আবার দিন।", "keypad", PIN_LEN)
        status, left = db.check_pin(self.user_id, pin)
        if status == "ok":
            self.state = S_MENU
            user = self._user()
            name_spoken = user.get('name_tts') or name_for_speech(user['name'])
            if not user.get('name_tts'):
                db.set_name_tts(self.user_id, name_spoken)
            return reply(f"হ্যালো {name_spoken} স্যার, আপনাকে কীভাবে সাহায্য করতে পারি?")
        if status == "locked":
            return self._end("সিকিউরিটির জন্য আপনার একাউন্ট লক করা হয়েছে। "
                             "দয়া করে ১৬২৬৮ এ কল করুন।")
        return reply(f"পিন ভুল হয়েছে। আর {left} বার ট্রাই করতে পারবেন।", "keypad", PIN_LEN)

    def _on_menu(self, kind, value):
        if kind != "speech":
            return reply("মুখে বলে জানান, আপনি কী করতে চান।")
        it = parse_intent(value)
        name = it["intent"]
        if name == "cash_out":
            self.ctx = {"action": "cash_out", "num_tries": 0, "amt_tries": 0}
            return self._ask_number()
        if name == "balance":
            return self._menu(f"আপনার ব্যালেন্স {self._user()['balance']} টাকা। ")
        if name == "spending":
            return self._spending(it["month"])
        if name == "send_money":
            target = it.get("target_name")
            if target:
                contacts = db.get_contacts(self.user_id)
                for c in contacts:
                    if target.lower() in c["name"].lower():
                        self.ctx = {"action": "send_money", "number": c["phone_number"], "name": c["name"], "amt_tries": 0}
                        return self._ask_amount(prefix=f"{c['name']} কে সেন্ড মানি করা হচ্ছে। ")
                return self._menu(f"{target} নামে কোনো কন্টাক্ট পাওয়া যায়নি। ")
            self.ctx = {"action": "send_money", "num_tries": 0, "amt_tries": 0}
            return self._ask_number("কাকে সেন্ড মানি করবেন? ")
        if name == "faq":
            return self._faq(it.get("question", value))
        if name == "bye" or (name == "unknown" and yes_no(value) is False):
            return self._end("ধন্যবাদ। আপনার দিনটি শুভ হোক।")
        self.fails += 1
        if self.fails >= MAX_TRIES:
            return self._end("দুঃখিত, আমি বুঝতে পারছি না। দয়া করে ১৬২৬৮ এ কল করুন।")
        return reply("দুঃখিত, বুঝতে পারিনি। আপনি ক্যাশ আউট, ব্যালেন্স, বা খরচের হিসাব জানতে পারেন।")

    def _spending(self, which):
        today = dt.date.today()
        y, m = (today.year, today.month) if which == "this" else (
            (today.year - 1, 12) if today.month == 1 else (today.year, today.month - 1))
        total, top = db.spending_summary(self.user_id, y, m)
        label = f"{MONTHS[m - 1]} মাসে"
        if total == 0:
            return self._menu(f"{label} আপনার কোনো খরচ নেই। ")
        extra = f", সবচেয়ে বেশি খরচ হয়েছে {KINDS.get(top[0], top[0])} এ, {top[1]} টাকা" if top else ""
        return self._menu(f"{label} আপনার মোট খরচ {total} টাকা{extra}। ")

    def _faq(self, question):
        """Answer FAQ questions using LLM + knowledge base."""
        try:
            from .llm_nlu import faq_answer
            answer = faq_answer(question)
            return self._menu(f"{answer} ")
        except Exception:
            return self._menu("এই বিষয়ে আরো জানতে হেল্পলাইন 16268 এ কল করুন। ")

    def _on_number(self, kind, value):
        if kind != "keypad":
            return self._need_keypad(11)
        num = normalize_digits(value)
        user = self._user()
        problem = None
        if len(num) != 11:
            problem = f"নম্বরটি ১১ ডিজিটের হতে হবে, আপনি {len(num)} ডিজিট দিয়েছেন। "
        elif not re.fullmatch(r"01[3-9]\d{8}", num):
            problem = "নম্বরটি ০১৩ থেকে ০১৯ এর মধ্যে শুরু হতে হবে। "
        elif num == user["phone"]:
            problem = "নিজের নম্বরে ক্যাশ আউট করা যায় না। "
        if problem:
            self.ctx["num_tries"] += 1
            if self.ctx["num_tries"] >= MAX_TRIES:
                return self._cancel("অনেকবার ভুল নম্বর দেওয়া হয়েছে")
            return self._ask_number(problem + "আবার ট্রাই করুন। ")
        self.ctx["number"] = num
        self.state = S_NUM_OK
        return reply(f"আমি আবার কনফার্ম করছি, নম্বরটি {num}। ঠিক থাকলে {YN_HINT}")

    def _on_number_ok(self, kind, value):
        ans = yes_no(value, kind)
        if ans is True:
            return self._ask_amount()
        if ans is False:
            self.ctx["num_tries"] += 1
            if self.ctx["num_tries"] >= MAX_TRIES:
                return self._cancel("নম্বর কনফার্ম করা যায়নি")
            return self._ask_number("ঠিক আছে। ")
        return reply(f"বুঝতে পারিনি। নম্বরটি {self.ctx['number']}। ঠিক থাকলে {YN_HINT}")

    def _on_amount(self, kind, value):
        if kind != "keypad":
            return self._need_keypad()
        digits = normalize_digits(value)
        amount = int(digits) if digits else 0
        user = self._user()
        problem = None
        if amount <= 0:
            problem = "সঠিক অ্যামাউন্ট দিন। "
        elif amount > user["max_txn_limit"]:
            problem = (f"আপনার সেট করা লিমিট {user['max_txn_limit']} টাকা। "
                       f"{amount} টাকা এই লিমিটের বেশি। ")
        elif amount > user["balance"]:
            problem = "আপনার ব্যালেন্স যথেষ্ট নয়। "
        if problem:
            self.ctx["amt_tries"] += 1
            if self.ctx["amt_tries"] >= 2:
                return self._cancel(problem)
            return self._ask_amount(problem + "কম অ্যামাউন্ট দিন। ")
        self.ctx["amount"] = amount
        # ── T4: Personalized Risk Scoring (replaces fixed half-balance heuristic) ──
        risk = db.get_risk_signals(self.user_id, self.ctx["number"], amount)
        self.ctx["risk"] = risk  # store for explainability (T16)
        risky = risk["is_risky"]
        if risky:
            self.state = S_RISK
            # T16: Explainable risk warning — tell user WHY the warning fired
            factors_text = "। ".join(risk["factors"][:3])
            score_pct = int(risk["score"] * 100)
            return reply(
                f"সতর্কতা (ঝুঁকি স্কোর: {score_pct}%): {factors_text}। "
                "কেউ কি ফোনে আপনাকে টাকা দিতে চাপ দিচ্ছে? "
                "যদি এটা পুরোপুরি আপনার নিজের সিদ্ধান্ত হয়, তাহলে 'হ্যাঁ' বলুন।")
        return self._ask_final()

    def _on_risk(self, kind, value):
        ans = yes_no(value, kind)
        if ans is True:
            return self._ask_final()
        if ans is False:
            return self._cancel("নিরাপত্তার কারণে")
        return reply("এটা আপনার নিজের সিদ্ধান্ত হলে 'হ্যাঁ', না হলে 'না' বলুন।")

    def _ask_final(self):
        self.state = S_FINAL
        action_text = "সেন্ড মানি" if self.ctx.get("action") == "send_money" else "ক্যাশ আউট"
        name_str = f"{self.ctx['name']} ({self.ctx['number']}) কে" if self.ctx.get("name") else f"{self.ctx['number']} নম্বরে"
        return reply(f"আপনি কি {name_str}, {self.ctx['amount']} টাকা {action_text} করতে চান? "
                     f"কনফার্ম করতে 'হ্যাঁ' বলুন।")

    def _on_final(self, kind, value):
        ans = yes_no(value, kind)
        action_text = "সেন্ড মানি" if self.ctx.get("action") == "send_money" else "ক্যাশ আউট"
        if ans is True:
            if self.ctx.get("action") == "send_money":
                bal = db.send_money(self.user_id, self.ctx["number"], self.ctx["amount"])
                if bal == "cooldown":
                    return self._cancel("গত ১০ মিনিটের মধ্যে এই নম্বরে একবার সেন্ড মানি করা হয়েছে")
                elif bal == "limit":
                    return self._cancel("আপনার সেট করা লিমিটের চেয়ে বেশি টাকা")
            else:
                bal = db.cash_out(self.user_id, self.ctx["number"], self.ctx["amount"])
            if bal is None:  # backend re-checks limit + balance
                return self._cancel("ব্যালেন্স বা লিমিটের কারণে ট্রানজেকশন হয়নি")
            return self._menu(f"সফল হয়েছে। {self.ctx['amount']} টাকা {action_text} করা হয়েছে। "
                              f"নতুন ব্যালেন্স {bal} টাকা। ")
        if ans is False:
            return self._cancel("ঠিক আছে")
        return reply(f"বুঝতে পারিনি। {action_text} করতে 'হ্যাঁ', ক্যানসেল করতে 'না' বলুন।")
