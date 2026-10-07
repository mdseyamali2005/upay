"""Bangla speech-text helpers.

Provides:
  phone_to_speech(num)  — phone number → Bangla spoken form with pauses
  speakable(text)       — full pipeline: phones, amounts, digits
  name_for_speech(name) — Latin name → Bangla transliteration (via Gemini, cached)
"""
import re
import logging

log = logging.getLogger(__name__)

BN_DIGITS = "০১২৩৪৫৬৭৮৯"
BN_WORDS = ["শূন্য", "এক", "দুই", "তিন", "চার", "পাঁচ", "ছয়", "সাত", "আট", "নয়"]
_TO_BN = str.maketrans("0123456789", BN_DIGITS)
_TO_ASCII = str.maketrans(BN_DIGITS, "0123456789")

# ── In-memory cache for name transliteration ──
_name_cache: dict[str, str] = {}


def _is_bangla(text: str) -> bool:
    """True if the text is predominantly Bangla script."""
    bangla = sum(1 for c in text if "\u0980" <= c <= "\u09FF")
    latin = sum(1 for c in text if "A" <= c.upper() <= "Z")
    return bangla > latin


def phone_to_speech(num: str) -> str:
    """Convert a phone number to Bangla spoken form.

    Keeps the last 11 digits, splits into groups 3-4-4,
    reads each digit as a Bangla word, joins digits with spaces
    and groups with ", " so TTS pauses between groups.

    >>> phone_to_speech("01755555555")
    'শূন্য এক সাত, পাঁচ পাঁচ পাঁচ পাঁচ, পাঁচ পাঁচ পাঁচ'
    """
    # normalise to ASCII digits only
    digits = re.sub(r"\D", "", num.translate(_TO_ASCII))
    # keep the last 11 digits (strip +88 / 88 prefix)
    if len(digits) > 11:
        digits = digits[-11:]
    if not digits:
        return num

    words = [BN_WORDS[int(d)] for d in digits]

    # split into groups 3-4-4
    groups = []
    if len(words) >= 11:
        groups = [words[0:3], words[3:7], words[7:11]]
    elif len(words) >= 7:
        groups = [words[0:3], words[3:7], words[7:]]
    elif len(words) >= 3:
        groups = [words[0:3], words[3:]]
    else:
        groups = [words]

    return ", ".join(" ".join(g) for g in groups if g)


def _digits_to_bangla(match: re.Match) -> str:
    """Replace a sequence of ASCII digits with Bangla digits."""
    return match.group().translate(_TO_BN)


# pattern: Bangladeshi phone numbers with optional +88/88 prefix
_BD_PHONE_RE = re.compile(
    r"(?:\+?88)?0[13-9]\d{8,9}"
)

# pattern: money markers
_MONEY_RE = re.compile(r"\b(?:TK|BDT|Tk|taka|TAKA)\b", re.IGNORECASE)

# pattern: remaining ASCII digits
_DIGIT_RE = re.compile(r"\d+")


def speakable(text: str) -> str:
    """Make text ready for Bangla TTS.

    1. Replace Bangladeshi phone numbers with Bangla-word spoken form.
    2. Replace TK/BDT with টাকা.
    3. Convert remaining Latin digits to Bangla digits.

    Display text on screen should stay unchanged — use speakable() only
    on the string that goes to the TTS engine.
    """
    if not text:
        return text

    # Step 1: replace phone numbers (longest match first)
    def _phone_replacer(m: re.Match) -> str:
        return phone_to_speech(m.group())

    result = _BD_PHONE_RE.sub(_phone_replacer, text)

    # Step 2: replace money markers
    result = _MONEY_RE.sub("টাকা", result)

    # Step 3: remaining ASCII digits → Bangla digits
    result = _DIGIT_RE.sub(_digits_to_bangla, result)

    return result


def name_for_speech(name: str) -> str:
    """Transliterate a Latin-script name to Bangla as pronounced in Bangladesh.

    If the name is already in Bangla script, returns it unchanged.
    Results are cached in memory. Uses Gemini LLM if available, else
    returns the original name.
    """
    if not name or _is_bangla(name):
        return name

    # check cache
    key = name.strip().upper()
    if key in _name_cache:
        return _name_cache[key]

    # try Gemini transliteration
    try:
        from .llm_nlu import _get_model
        model = _get_model()
        if model is None:
            return name
        import google.generativeai as genai
        response = model.generate_content(
            f"Transliterate this Bangladeshi person's name to Bangla script "
            f"(as pronounced in Bangladesh). Return ONLY the Bangla script, "
            f"nothing else.\n\nName: {name}",
            generation_config=genai.GenerationConfig(
                temperature=0.0,
                max_output_tokens=50,
            ),
        )
        bn_name = response.text.strip()
        if bn_name and _is_bangla(bn_name):
            _name_cache[key] = bn_name
            return bn_name
    except Exception as e:
        log.warning("name transliteration failed: %s", e)

    return name
