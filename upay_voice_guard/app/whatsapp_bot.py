"""upay Voice Guard — WhatsApp Bot Interface.

WhatsApp Business Cloud API integration that mirrors the Telegram bot
call-flow experience with interactive buttons and voice note support.

Environment variables:
    WHATSAPP_TOKEN          — Permanent or temporary access token from Meta
    WHATSAPP_PHONE_ID       — Phone number ID from Meta dashboard
    WHATSAPP_VERIFY_TOKEN   — Custom string to verify webhook (you set it)

The bot is mounted as a sub-router in main.py at /whatsapp/webhook.
"""
import io
import logging
import os
import re

import httpx
from fastapi import APIRouter, Request, Response

from . import db
from .flow import Session
from .stt import transcribe

log = logging.getLogger(__name__)

# ── Configuration ──
WA_TOKEN = lambda: os.environ.get("WHATSAPP_TOKEN", "")
WA_PHONE_ID = lambda: os.environ.get("WHATSAPP_PHONE_ID", "")
WA_VERIFY = lambda: os.environ.get("WHATSAPP_VERIFY_TOKEN", "upay-voice-guard")
WA_API = "https://graph.facebook.com/v21.0"

# ── Session & keypad buffer storage (per phone number) ──
_sessions: dict[str, Session] = {}
_keypad_buffers: dict[str, str] = {}


# ═══════════════════════════════════════════════════════════════════════
# WhatsApp Cloud API helpers
# ═══════════════════════════════════════════════════════════════════════

def _headers():
    return {
        "Authorization": f"Bearer {WA_TOKEN()}",
        "Content-Type": "application/json",
    }


def _send_text(to: str, text: str):
    """Send a plain text message."""
    url = f"{WA_API}/{WA_PHONE_ID()}/messages"
    body = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "text",
        "text": {"preview_url": False, "body": text},
    }
    try:
        r = httpx.post(url, json=body, headers=_headers(), timeout=15)
        r.raise_for_status()
    except Exception as e:
        log.error("WhatsApp send_text failed: %s", e)


def _send_interactive_buttons(to: str, body_text: str, buttons: list[dict]):
    """Send an interactive message with up to 3 reply buttons.
    buttons: [{"id": "btn_1", "title": "হ্যাঁ"}, ...]
    WhatsApp allows max 3 buttons per message.
    """
    url = f"{WA_API}/{WA_PHONE_ID()}/messages"
    btn_list = [{"type": "reply", "reply": b} for b in buttons[:3]]
    payload = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "interactive",
        "interactive": {
            "type": "button",
            "body": {"text": body_text},
            "action": {"buttons": btn_list},
        },
    }
    try:
        r = httpx.post(url, json=payload, headers=_headers(), timeout=15)
        r.raise_for_status()
    except Exception as e:
        log.error("WhatsApp send_interactive failed: %s", e)


def _send_interactive_list(to: str, body_text: str, button_text: str, sections: list[dict]):
    """Send an interactive list message (menu with many options).
    sections: [{"title": "Section", "rows": [{"id": "...", "title": "...", "description": "..."}]}]
    """
    url = f"{WA_API}/{WA_PHONE_ID()}/messages"
    payload = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "interactive",
        "interactive": {
            "type": "list",
            "body": {"text": body_text},
            "action": {
                "button": button_text,
                "sections": sections,
            },
        },
    }
    try:
        r = httpx.post(url, json=payload, headers=_headers(), timeout=15)
        r.raise_for_status()
    except Exception as e:
        log.error("WhatsApp send_list failed: %s", e)


def _download_media(media_id: str) -> bytes:
    """Download a media file (voice note) from WhatsApp."""
    # Step 1: Get the media URL
    url = f"{WA_API}/{media_id}"
    r = httpx.get(url, headers=_headers(), timeout=15)
    r.raise_for_status()
    media_url = r.json().get("url", "")

    # Step 2: Download the actual binary
    r2 = httpx.get(media_url, headers=_headers(), timeout=30)
    r2.raise_for_status()
    return r2.content


def _mark_read(message_id: str):
    """Mark a message as read (blue ticks)."""
    url = f"{WA_API}/{WA_PHONE_ID()}/messages"
    body = {
        "messaging_product": "whatsapp",
        "status": "read",
        "message_id": message_id,
    }
    try:
        httpx.post(url, json=body, headers=_headers(), timeout=10)
    except Exception:
        pass


# ═══════════════════════════════════════════════════════════════════════
# Response formatting & keyboard logic
# ═══════════════════════════════════════════════════════════════════════

def _format_response(data: dict) -> str:
    """Format the agent response with status indicators."""
    say = data["say"]
    is_warning = "সতর্কতা" in say

    if data.get("end"):
        return f"🏁 *কল শেষ*\n\n{say}"
    elif is_warning:
        return f"⚠️ *সতর্কতা*\n\n{say}"
    elif data.get("expect") == "keypad":
        return f"🔢 *Keypad required*\n\n{say}\n\n_কীপ্যাডে নম্বর/PIN/টাকা টাইপ করে পাঠান।_"
    else:
        return f"🗣️ *Voice input*\n\n{say}"


def _send_response(to: str, data: dict):
    """Send the formatted response with appropriate interactive elements."""
    text = _format_response(data)

    if data.get("end"):
        _send_text(to, text + "\n\nনতুন কল শুরু করতে *start* লিখুন।")
        return

    expect = data.get("expect", "speech")

    if expect == "keypad":
        # For keypad input, just send text — user types the number
        _send_text(to, text)

    elif expect == "speech":
        # Send interactive buttons for common speech actions
        # WhatsApp allows max 3 buttons, so prioritize the most useful ones
        # We'll send a button group + a separate list for more options
        buttons = [
            {"id": "say_হ্যাঁ", "title": "✅ হ্যাঁ"},
            {"id": "say_না", "title": "❌ না"},
        ]

        # Check context to decide the third button
        if "কীভাবে সাহায্য" in data["say"] or "আর কিছু" in data["say"]:
            # Menu state — show main actions
            _send_interactive_buttons(to, text, [
                {"id": "say_cash_out", "title": "💸 ক্যাশ আউট"},
                {"id": "say_balance", "title": "💰 ব্যালেন্স"},
                {"id": "say_bye", "title": "👋 বিদায়"},
            ])
            # Also send a list with more options
            _send_interactive_list(to, "আরও সেবা দেখুন:", "🔽 আরও সেবা", [
                {
                    "title": "upay সেবা",
                    "rows": [
                        {"id": "say_cash_out", "title": "💸 ক্যাশ আউট", "description": "এজেন্ট থেকে টাকা তুলুন"},
                        {"id": "say_balance", "title": "💰 ব্যালেন্স", "description": "একাউন্টের ব্যালেন্স দেখুন"},
                        {"id": "say_spending_this", "title": "📊 এই মাসের খরচ", "description": "এই মাসের খরচের হিসাব"},
                        {"id": "say_spending_last", "title": "📊 গত মাসের খরচ", "description": "গত মাসের খরচের হিসাব"},
                        {"id": "say_bye", "title": "👋 বিদায়", "description": "কল শেষ করুন"},
                    ],
                },
            ])
        else:
            # Confirmation state — yes/no + cancel
            buttons.append({"id": "say_cancel", "title": "🚫 বাতিল"})
            _send_interactive_buttons(to, text, buttons)
    else:
        _send_text(to, text)


# ═══════════════════════════════════════════════════════════════════════
# Message processing core
# ═══════════════════════════════════════════════════════════════════════

def _process_text_input(phone: str, text: str):
    """Process a text message from the user."""
    text = text.strip()
    lower = text.lower()

    # ── Command: start a new session ──
    if lower in ("start", "/start", "শুরু", "নতুন", "hi", "hello", "হ্যালো"):
        _sessions.pop(phone, None)
        _keypad_buffers.pop(phone, None)

        db.init_db()
        session = Session()
        _sessions[phone] = session
        data = session.start()

        welcome = f"🤖 *upay Voice Guard*\n\n_ডেমো PIN: 1234_\n\n"
        _send_text(phone, welcome)
        _send_response(phone, data)
        return

    # ── Command: end session ──
    if lower in ("end", "/end", "শেষ", "stop"):
        _sessions.pop(phone, None)
        _keypad_buffers.pop(phone, None)
        _send_text(phone, "📞 কলটি শেষ হয়েছে।\nনতুন কল শুরু করতে *start* লিখুন।")
        return

    # ── Command: help ──
    if lower in ("help", "/help", "সাহায্য"):
        _send_text(
            phone,
            "🤖 *upay Voice Guard — WhatsApp Bot*\n\n"
            "এই বটটি আপনার upay Voice Guard এজেন্ট। "
            "কথা বলে বা কীপ্যাড দিয়ে টাকা পাঠান, ব্যালেন্স জানুন।\n\n"
            "*কমান্ড:*\n"
            "• *start* — নতুন কল শুরু করুন\n"
            "• *end* — কল শেষ করুন\n"
            "• *help* — সাহায্য\n\n"
            "*ব্যবহার:*\n"
            "• 🔢 PIN/নম্বর/টাকা সরাসরি টাইপ করুন\n"
            "• 🗣️ ভয়েস নোট পাঠান কথা বলতে\n"
            "• ✍️ বাংলায় টাইপ করুন\n"
            "• 🎯 Quick-action বাটন চাপুন\n\n"
            "_ডেমো PIN: 1234_",
        )
        return

    # ── No active session ──
    session = _sessions.get(phone)
    if not session:
        _send_text(
            phone,
            "❌ কোনো সক্রিয় সেশন নেই।\n*start* লিখে নতুন কল শুরু করুন।"
        )
        return

    # ── Determine input kind ──
    # If the session expects keypad and the input is all digits, treat as keypad
    # Otherwise treat as speech
    digits_only = re.fullmatch(r"[\d০-৯]+", text)

    if digits_only:
        kind = "keypad"
        value = text
    else:
        kind = "speech"
        value = text

    result = session.handle(kind, value)

    if result.get("end"):
        _sessions.pop(phone, None)
        _keypad_buffers.pop(phone, None)

    _send_response(phone, result)


def _process_button_reply(phone: str, button_id: str):
    """Process an interactive button / list selection reply."""
    session = _sessions.get(phone)
    if not session:
        _send_text(phone, "❌ কোনো সক্রিয় সেশন নেই।\n*start* লিখে নতুন কল শুরু করুন।")
        return

    # Map button IDs to speech inputs
    speech_map = {
        "say_cash_out": "ক্যাশ আউট করতে চাই",
        "say_balance": "ব্যালেন্স কত",
        "say_spending_this": "এই মাসে কত খরচ হয়েছে",
        "say_spending_last": "গত মাসে কত খরচ হয়েছে",
        "say_bye": "ধন্যবাদ",
        "say_হ্যাঁ": "হ্যাঁ",
        "say_না": "না",
        "say_cancel": "বাতিল",
    }

    # Extract the speech text from the button ID
    if button_id.startswith("say_"):
        speech_text = speech_map.get(button_id, button_id[4:])
    else:
        speech_text = button_id

    result = session.handle("speech", speech_text)

    if result.get("end"):
        _sessions.pop(phone, None)
        _keypad_buffers.pop(phone, None)

    _send_response(phone, result)


def _process_voice(phone: str, media_id: str):
    """Process a voice note — download, transcribe, and feed into session."""
    session = _sessions.get(phone)
    if not session:
        _send_text(phone, "❌ কোনো সক্রিয় সেশন নেই।\n*start* লিখে নতুন কল শুরু করুন।")
        return

    _send_text(phone, "🎙️ ভয়েস প্রসেস করা হচ্ছে...")

    try:
        audio_bytes = _download_media(media_id)
        transcript = transcribe(audio_bytes)
    except Exception as e:
        log.error("Voice download/transcribe failed: %s", e)
        _send_text(phone, "😶 ভয়েস থেকে কিছু বোঝা যায়নি। টেক্সটে লিখুন বা বাটন ব্যবহার করুন।")
        return

    if not transcript:
        _send_text(phone, "😶 ভয়েস থেকে কিছু বোঝা যায়নি। টেক্সটে লিখুন বা বাটন ব্যবহার করুন।")
        return

    _send_text(phone, f"🎙️ শুনেছি: _{transcript}_")

    result = session.handle("speech", transcript)

    if result.get("end"):
        _sessions.pop(phone, None)
        _keypad_buffers.pop(phone, None)

    _send_response(phone, result)


# ═══════════════════════════════════════════════════════════════════════
# FastAPI webhook router
# ═══════════════════════════════════════════════════════════════════════

router = APIRouter(prefix="/whatsapp", tags=["whatsapp"])


@router.get("/webhook")
async def verify_webhook(request: Request):
    """Webhook verification endpoint (Meta sends a GET to verify)."""
    params = request.query_params
    mode = params.get("hub.mode", "")
    token = params.get("hub.verify_token", "")
    challenge = params.get("hub.challenge", "")

    if mode == "subscribe" and token == WA_VERIFY():
        log.info("WhatsApp webhook verified successfully.")
        return Response(content=challenge, media_type="text/plain")

    log.warning("WhatsApp webhook verification failed: mode=%s", mode)
    return Response(content="Forbidden", status_code=403)


@router.post("/webhook")
async def receive_webhook(request: Request):
    """Handle incoming WhatsApp messages."""
    try:
        body = await request.json()
    except Exception:
        return {"status": "ok"}

    # Navigate the nested webhook payload structure
    for entry in body.get("entry", []):
        for change in entry.get("changes", []):
            value = change.get("value", {})
            messages = value.get("messages", [])

            for msg in messages:
                phone = msg.get("from", "")
                msg_type = msg.get("type", "")
                msg_id = msg.get("id", "")

                # Mark as read
                _mark_read(msg_id)

                if msg_type == "text":
                    text = msg.get("text", {}).get("body", "")
                    _process_text_input(phone, text)

                elif msg_type == "interactive":
                    interactive = msg.get("interactive", {})
                    itype = interactive.get("type", "")
                    if itype == "button_reply":
                        btn_id = interactive.get("button_reply", {}).get("id", "")
                        _process_button_reply(phone, btn_id)
                    elif itype == "list_reply":
                        list_id = interactive.get("list_reply", {}).get("id", "")
                        _process_button_reply(phone, list_id)

                elif msg_type in ("audio", "voice"):
                    audio_info = msg.get("audio", {}) or msg.get("voice", {})
                    media_id = audio_info.get("id", "")
                    if media_id:
                        _process_voice(phone, media_id)

                else:
                    # Unsupported message type
                    _send_text(
                        phone,
                        "এই ধরনের মেসেজ সাপোর্ট করা হয় না। "
                        "টেক্সট লিখুন, ভয়েস নোট পাঠান, বা বাটন চাপুন।"
                    )

    return {"status": "ok"}


def is_configured() -> bool:
    """Check if WhatsApp Bot environment variables are set."""
    return bool(WA_TOKEN() and WA_PHONE_ID())
