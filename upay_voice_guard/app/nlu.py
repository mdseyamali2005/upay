"""Small, dependency-free Bangla helpers: digits, yes/no, intent.
Swap parse_intent() for an LLM call later; keep the rest as-is.

Enhanced for:
  - Standard Bangla keywords
  - Banglish (romanized Bangla)
  - Regional dialects (Sylheti, Chittagong, Noakhali, Rangpur, Barishal)
  - Common ASR transcription errors
  - FAQ detection (questions about charges, limits, rules)
"""
import re
import unicodedata

BN_DIGITS = "০১২৩৪৫৬৭৮৯"
BN_WORDS = ["শূন্য", "এক", "দুই", "তিন", "চার", "পাঁচ", "ছয়", "সাত", "আট", "নয়"]
_TO_ASCII = str.maketrans(BN_DIGITS, "0123456789")
_TO_BN = str.maketrans("0123456789", BN_DIGITS)


def to_bn(n) -> str:
    """5000 -> ৫০০০"""
    return str(n).translate(_TO_BN)


def normalize_digits(text: str) -> str:
    """Bangla/English digits -> ascii digits; everything else dropped."""
    return re.sub(r"\D", "", str(text).translate(_TO_ASCII))


def spell_digits(num: str, group: int = 4) -> str:
    """'01712345678' -> 'শূন্য এক সাত এক, দুই তিন চার পাঁচ, ছয় সাত আট' (commas = TTS pauses)"""
    words = [BN_WORDS[int(c)] for c in num]
    return ", ".join(" ".join(words[i:i + group]) for i in range(0, len(words), group))


def _tokens(text: str):
    text = unicodedata.normalize("NFC", text.lower())
    # explicit Bengali block: \w would split words at vowel signs
    return re.findall(r"[\u0980-\u09FFa-z0-9]+", text)


_NO = {"না", "নাহ", "নাই", "নেই", "ভুল", "বাতিল", "no", "cancel", "নয়"}
_YES = {"হ্যাঁ", "হ্যা", "হাঁ", "হা", "হুম", "হুঁ", "জি", "ঠিক", "সঠিক", "ওকে",
        "ok", "okay", "yes", "কনফার্ম", "অবশ্যই"}


def yes_no(text: str, kind: str = "speech"):
    """True / False / None (unclear). Keypad fallback: 1 = yes, 2 = no.
    Negatives are checked first so 'ঠিক নাই' means no."""
    if kind == "keypad":
        d = normalize_digits(text)
        return True if d == "1" else False if d == "2" else None
    toks = set(_tokens(text))
    if toks & _NO:
        return False
    if toks & _YES:
        return True
    return None


# ── Intent keyword lists (Bangla + Banglish + Dialects + ASR errors) ──

_CASH = [
    # Standard Bangla
    "ক্যাশ", "ক্যাস", "cash", "তুলতে", "তুলব", "তুলবো", "তুলে", "তুলি",
    "উঠাতে", "উত্তোলন", "টাকা তুলতে", "cashout", "cash out",
    # Banglish
    "tulte", "tulbo", "tule",
    # Dialects: Sylheti, Chittagong, Noakhali, Rangpur, Barishal
    "তুলুম", "তুলাম", "পয়সা তুলতাম", "পয়সা তুল",
    "টেকা তুলতে", "ট্যাকা তুলুম", "টেকা তুল",
    # ASR errors
    "ক্যশ", "কেশ আউট", "কেস আউট",
]

_BAL = [
    # Standard Bangla
    "ব্যালেন্স", "ব্যালান্স", "balance", "কত টাকা আছে", "টাকা আছে কত",
    "জমা আছে", "হিসাব",
    # Banglish
    "koto taka", "taka ase", "koto ase",
    # Dialects
    "কত টেকা আছে", "টেকা আসে", "পয়সা আসে", "পইসা দেহি",
    "কত পয়সা", "কত পইসা",
    # ASR errors
    "ব্যলেন্স", "ব্যালেন", "জমা আসে",
]

_SPEND = [
    # Standard Bangla
    "খরচ", "খরছ", "spend", "ব্যয়", "কত গেছে", "কত খরচ", "spending",
    # Banglish
    "khoroch", "khorcha", "koto geche",
    # Dialects
    "খরচা", "খরচ হইসে", "খরচ হইছে",
    # ASR errors
    "খরস",
]

_SEND = [
    # Standard Bangla
    "সেন্ড", "পাঠাতে", "পাঠাব", "পাঠাবো", "send", "পাঠাও", "পাঠান", "পাঠাই",
    "সেন্ড মানি", "মানি",
    # Banglish
    "pathate", "pathabo", "pathaite", "pathao",
    # Dialects
    "পাঠাইতে", "পাডাইতে",
]

_BYE = {
    # Standard Bangla
    "ধন্যবাদ", "বাই", "রাখছি", "রাখি", "থ্যাঙ্ক", "bye", "বিদায়", "আস্সালামু",
    # Banglish
    "dhonnobad", "rakhi", "rakhchi",
    # Dialects
    "রাখো",
}

# ── FAQ detection: question words + financial/service terms ──
_FAQ_CONTEXT_MARKERS = [
    "চার্জ", "ফি", "fee", "charge",
    "লিমিট", "limit", "সর্বোচ্চ", "সর্বনিম্ন",
    "রিসেট", "reset", "ভুলে গেলে",
    "কিভাবে", "kibhabe", "নিয়ম", "rule",
    "কোথায়", "কোথা", "where",
    "অভিযোগ", "complaint", "হেল্পলাইন",
    "নিরাপত্তা", "security",
    "কি লাগে", "ki lage",
    "কত লাগে",
    "সাহায্য",
    "একাউন্ট খুল",
    # Daily limit / withdrawal questions
    "দৈনিক", "তোলা যায়", "কত যায়",
]


def _is_faq(text: str) -> bool:
    """Detect if text is asking a question about services/rules (FAQ) rather
    than requesting an action."""
    t = text.lower()
    if any(marker in t for marker in _FAQ_CONTEXT_MARKERS):
        return True
    return False


# ── Send money target name extraction ──
# Common action/amount words that should NOT be treated as names
_NOT_NAMES = {
    "টাকা", "taka", "send", "money", "সেন্ড", "মানি", "পাঠাও", "পাঠা", "পাঠাতে",
    "পাঠাব", "পাঠাবো", "কর", "করো", "দাও", "দে", "মোবাইল", "কত", "koro", "dao",
    "pathao", "korte", "chai", "ami", "আমি", "আমার", "kor", "pathaite", "পাঠাইতে",
    "করতে", "চাই", "হবে", "করবো", "করব",
}
# Digits (Bangla & English) to detect amount strings
_DIGIT_RE = re.compile(r'^[\d০-৯]+$')


def _extract_send_target(text: str) -> str | None:
    """Extract target person name from send money voice input.
    
    Handles patterns like:
      - "রাকিবকে ৫০০ টাকা সেন্ড কর" → "রাকিব"
      - "রাকিব কে 500 টাকা পাঠাও" → "রাকিব"
      - "rakib ke send koro" → "rakib"
    """
    t = unicodedata.normalize("NFC", text.strip())
    
    # Pattern 1: "Xকে" (name with কে suffix attached), e.g. "রাকিবকে"
    m = re.search(r'([\u0980-\u09FF]+?)কে(?:\s|$)', t)
    if m:
        name = m.group(1)
        if name.lower() not in _NOT_NAMES and not _DIGIT_RE.match(name) and len(name) >= 2:
            return name
    
    # Pattern 2: "X কে" (name followed by কে as separate word)
    m = re.search(r'([\u0980-\u09FF]{2,})\s+কে(?:\s|$)', t)
    if m:
        name = m.group(1)
        if name.lower() not in _NOT_NAMES and not _DIGIT_RE.match(name):
            return name
    
    # Pattern 3: Banglish "X ke" (e.g. "rakib ke send koro")
    m = re.search(r'\b([a-zA-Z]{2,})\s+ke\b', t, re.IGNORECASE)
    if m:
        name = m.group(1)
        if name.lower() not in _NOT_NAMES and not _DIGIT_RE.match(name):
            return name
    
    # Pattern 4: "X র কাছে" / "Xএর কাছে" (to someone)
    m = re.search(r'([\u0980-\u09FF]{2,})(?:র|এর)\s+কাছে', t)
    if m:
        name = m.group(1)
        if name.lower() not in _NOT_NAMES and not _DIGIT_RE.match(name):
            return name
    
    return None


def parse_intent(text: str) -> dict:
    # Try LLM-based parsing first (requires GEMINI_API_KEY)
    try:
        from .llm_nlu import llm_parse_intent
        result = llm_parse_intent(text)
        if result and result.get("intent") != "unknown":
            return result
    except Exception:
        pass

    # Fall back to enhanced rule-based parsing
    t = unicodedata.normalize("NFC", text.lower())

    # ── FAQ detection first (before action intents) ──
    # If the text contains question markers alongside action words,
    # it's asking about the service, not requesting an action.
    if _is_faq(t):
        return {"intent": "faq", "question": text}

    # ── Compound negation: "X না Y" → extract the affirmed intent ──
    neg_match = re.search(r'(.+?)\s+না\s+(.+)', t)
    if neg_match:
        # The part after "না" is what the user actually wants
        affirmed = neg_match.group(2)
        return parse_intent(affirmed)

    # ── Action intents ──
    if any(w in t for w in _SPEND):
        month = "this" if ("এই মাস" in t or "this month" in t or "ei mas" in t or "ei month" in t) else "last"
        return {"intent": "spending", "month": month}
    if any(w in t for w in _CASH):
        return {"intent": "cash_out"}
    if any(w in t for w in _BAL):
        return {"intent": "balance"}
    if any(w in t for w in _SEND):
        # Try to extract target_name from the text
        target_name = _extract_send_target(text)
        result = {"intent": "send_money"}
        if target_name:
            result["target_name"] = target_name
        return result
    if set(_tokens(t)) & _BYE:
        return {"intent": "bye"}

    # ── Banglish fallback patterns ──
    banglish_patterns = {
        "cash_out": r"\b(cash\s*out|taka\s*tul|tul\w*\s*chai|cashout)\b",
        "balance": r"\b(balance|taka\s*ase|koto\s*taka|joma\s*ase)\b",
        "spending": r"\b(spending|khoroch|khorcha|koto\s*geche)\b",
        "send_money": r"\b(send\s*money|taka\s*patha|pathate|pathaite)\b",
        "bye": r"\b(bye|dhonnobad|rakhchi|rakhi)\b",
        "faq": r"\b(charge\s*koto|kibhabe|pin\s*reset|limit\s*koto)\b",
    }
    for intent, pattern in banglish_patterns.items():
        if re.search(pattern, t):
            if intent == "spending":
                month = "this" if re.search(r"\b(ei\s*mas|this\s*month|ei\s*month)\b", t) else "last"
                return {"intent": intent, "month": month}
            if intent == "faq":
                return {"intent": intent, "question": text}
            if intent == "send_money":
                target_name = _extract_send_target(text)
                result = {"intent": "send_money"}
                if target_name:
                    result["target_name"] = target_name
                return result
            return {"intent": intent}

    return {"intent": "unknown"}
