"""upay Voice Guard — Telegram Bot Interface.

A Telegram bot with inline dialpad keyboard and voice note support.
Mirrors the call-flow experience from the web UI.

Usage:
    TELEGRAM_BOT_TOKEN=your_token python -m app.telegram_bot

Or run alongside FastAPI by importing and calling start_telegram_bot().
"""
import asyncio
import logging
import os
import sys

# Add parent dir to path for imports when running standalone
if __name__ == "__main__":
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import db
from app.flow import Session
from app.stt import transcribe

log = logging.getLogger(__name__)

try:
    from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
    from telegram.ext import (
        Application, CommandHandler, MessageHandler, CallbackQueryHandler,
        ContextTypes, filters
    )
    TELEGRAM_AVAILABLE = True
except ImportError:
    TELEGRAM_AVAILABLE = False
    log.warning("python-telegram-bot not installed. Run: pip install python-telegram-bot")

# ── Session storage (per-chat) ──
_sessions: dict[int, Session] = {}

# ── Bangla keypad layouts ──

def _pin_keyboard():
    """4-digit PIN entry keyboard."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(1, 4)],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(4, 7)],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(7, 10)],
        [InlineKeyboardButton("⌫", callback_data="key_back"),
         InlineKeyboardButton("0", callback_data="key_0"),
         InlineKeyboardButton("✅ পাঠান", callback_data="key_send")],
    ])


def _number_keyboard():
    """11-digit mobile number entry keyboard."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(1, 4)],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(4, 7)],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(7, 10)],
        [InlineKeyboardButton("⌫", callback_data="key_back"),
         InlineKeyboardButton("0", callback_data="key_0"),
         InlineKeyboardButton("✅ পাঠান", callback_data="key_send")],
    ])


def _amount_keyboard():
    """Quick-pick amounts + custom keyboard."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("৫০০ ৳", callback_data="amt_500"),
         InlineKeyboardButton("১০০০ ৳", callback_data="amt_1000"),
         InlineKeyboardButton("২০০০ ৳", callback_data="amt_2000")],
        [InlineKeyboardButton("৩০০০ ৳", callback_data="amt_3000"),
         InlineKeyboardButton("৫০০০ ৳", callback_data="amt_5000")],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(1, 4)],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(4, 7)],
        [InlineKeyboardButton(str(i), callback_data=f"key_{i}") for i in range(7, 10)],
        [InlineKeyboardButton("⌫", callback_data="key_back"),
         InlineKeyboardButton("0", callback_data="key_0"),
         InlineKeyboardButton("✅ পাঠান", callback_data="key_send")],
    ])


def _speech_keyboard():
    """Quick speech actions as inline buttons."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💸 ক্যাশ আউট", callback_data="say_ক্যাশ আউট করতে চাই"),
         InlineKeyboardButton("💰 ব্যালেন্স", callback_data="say_ব্যালেন্স কত")],
        [InlineKeyboardButton("📊 খরচের হিসাব", callback_data="say_গত মাসে কত খরচ হয়েছে"),
         InlineKeyboardButton("👋 বিদায়", callback_data="say_ধন্যবাদ")],
        [InlineKeyboardButton("✅ হ্যাঁ", callback_data="say_হ্যাঁ"),
         InlineKeyboardButton("❌ না", callback_data="say_না")],
    ])


def _get_keyboard(expect: str, digits=None):
    """Choose the right keyboard for the current flow state."""
    if expect == "keypad":
        if digits == 4:
            return _pin_keyboard()
        elif digits == 11:
            return _number_keyboard()
        else:
            return _amount_keyboard()
    elif expect == "speech":
        return _speech_keyboard()
    return None


def _format_response(data: dict) -> str:
    """Format the agent response with status indicators."""
    say = data["say"]
    is_warning = "সতর্কতা" in say

    if data.get("end"):
        return f"🏁 *কল শেষ*\n\n{say}"
    elif is_warning:
        return f"⚠️ *সতর্কতা*\n\n{say}"
    elif data.get("expect") == "keypad":
        return f"🔢 *Keypad required*\n\n{say}"
    else:
        return f"🗣️ *Voice input*\n\n{say}"


# ── Input buffer for keypad entries ──
_keypad_buffers: dict[int, str] = {}


# ── Handlers ──

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Start a new voice guard session."""
    chat_id = update.effective_chat.id

    # Clean up old session
    _sessions.pop(chat_id, None)
    _keypad_buffers[chat_id] = ""

    db.init_db()
    session = Session()
    _sessions[chat_id] = session
    data = session.start()

    kb = _get_keyboard(data["expect"], data.get("digits"))
    text = _format_response(data)

    await update.message.reply_text(
        f"🤖 *upay Voice Guard*\n\n{text}\n\n_Demo PIN: `1234`_",
        parse_mode="Markdown",
        reply_markup=kb
    )


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show help message."""
    await update.message.reply_text(
        "🤖 *upay Voice Guard — Telegram Bot*\n\n"
        "এই বটটি আপনার upay Voice Guard এজেন্ট। "
        "কথা বলে বা কীপ্যাড দিয়ে টাকা পাঠান, ব্যালেন্স জানুন।\n\n"
        "*কমান্ড:*\n"
        "/start — নতুন কল শুরু করুন\n"
        "/end — কল শেষ করুন\n"
        "/help — সাহায্য\n\n"
        "*ব্যবহার:*\n"
        "• 🔢 কীপ্যাড বাটন চাপুন PIN/নম্বর/টাকা দিতে\n"
        "• 🗣️ ভয়েস নোট পাঠান কথা বলতে\n"
        "• ✍️ টেক্সট টাইপ করতে পারেন\n"
        "• 🎯 Quick-action বাটন চাপুন\n\n"
        "_Demo PIN: `1234`_",
        parse_mode="Markdown"
    )


async def cmd_end(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """End the current session."""
    chat_id = update.effective_chat.id
    _sessions.pop(chat_id, None)
    _keypad_buffers.pop(chat_id, None)
    await update.message.reply_text(
        "📞 কলটি শেষ হয়েছে।\nনতুন কল শুরু করতে /start চাপুন।",
        parse_mode="Markdown"
    )


async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle inline keyboard button presses."""
    query = update.callback_query
    await query.answer()

    chat_id = query.message.chat.id
    data_str = query.data

    session = _sessions.get(chat_id)
    if not session:
        await query.edit_message_text(
            "❌ কোনো সক্রিয় সেশন নেই। /start দিয়ে শুরু করুন।"
        )
        return

    # Handle speech quick-action buttons
    if data_str.startswith("say_"):
        speech_text = data_str[4:]
        result = session.handle("speech", speech_text)
        text = _format_response(result)
        kb = _get_keyboard(result["expect"], result.get("digits")) if not result.get("end") else None

        if result.get("end"):
            _sessions.pop(chat_id, None)
            _keypad_buffers.pop(chat_id, None)

        _keypad_buffers[chat_id] = ""
        await query.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)
        return

    # Handle quick amount buttons
    if data_str.startswith("amt_"):
        amount = data_str[4:]
        result = session.handle("keypad", amount)
        text = _format_response(result)
        kb = _get_keyboard(result["expect"], result.get("digits")) if not result.get("end") else None

        if result.get("end"):
            _sessions.pop(chat_id, None)
            _keypad_buffers.pop(chat_id, None)

        _keypad_buffers[chat_id] = ""
        await query.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)
        return

    # Handle keypad digit entry
    if data_str.startswith("key_"):
        key = data_str[4:]

        if chat_id not in _keypad_buffers:
            _keypad_buffers[chat_id] = ""

        if key == "back":
            _keypad_buffers[chat_id] = _keypad_buffers[chat_id][:-1]
            display = _keypad_buffers[chat_id] or "..."
            await query.edit_message_text(
                f"🔢 কীপ্যাড ইনপুট: `{display}`",
                parse_mode="Markdown",
                reply_markup=query.message.reply_markup
            )
            return

        if key == "send":
            buf = _keypad_buffers.get(chat_id, "")
            if not buf:
                return

            result = session.handle("keypad", buf)
            text = _format_response(result)
            kb = _get_keyboard(result["expect"], result.get("digits")) if not result.get("end") else None

            if result.get("end"):
                _sessions.pop(chat_id, None)
                _keypad_buffers.pop(chat_id, None)
            else:
                _keypad_buffers[chat_id] = ""

            await query.edit_message_text(text, parse_mode="Markdown", reply_markup=kb)
            return

        # Regular digit press
        _keypad_buffers[chat_id] += key
        display = _keypad_buffers[chat_id]
        await query.edit_message_text(
            f"🔢 কীপ্যাড ইনপুট: `{display}`",
            parse_mode="Markdown",
            reply_markup=query.message.reply_markup
        )


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle text messages as speech input."""
    chat_id = update.effective_chat.id
    session = _sessions.get(chat_id)
    if not session:
        await update.message.reply_text(
            "❌ কোনো সক্রিয় সেশন নেই। /start দিয়ে শুরু করুন।"
        )
        return

    text_input = update.message.text.strip()
    if not text_input:
        return

    result = session.handle("speech", text_input)
    text = _format_response(result)
    kb = _get_keyboard(result["expect"], result.get("digits")) if not result.get("end") else None

    if result.get("end"):
        _sessions.pop(chat_id, None)
        _keypad_buffers.pop(chat_id, None)

    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=kb)


async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle voice notes — transcribe and process as speech input."""
    chat_id = update.effective_chat.id
    session = _sessions.get(chat_id)
    if not session:
        await update.message.reply_text(
            "❌ কোনো সক্রিয় সেশন নেই। /start দিয়ে শুরু করুন।"
        )
        return

    # Download voice note
    voice = update.message.voice
    file = await context.bot.get_file(voice.file_id)
    audio_bytes = await file.download_as_bytearray()

    # Transcribe
    status_msg = await update.message.reply_text("🎙️ ভয়েস প্রসেস করা হচ্ছে...")
    transcript = transcribe(bytes(audio_bytes))

    if not transcript:
        await status_msg.edit_text(
            "😶 ভয়েস থেকে কিছু বোঝা যায়নি। টেক্সটে লিখুন বা Quick-action বাটন ব্যবহার করুন।"
        )
        return

    await status_msg.edit_text(f"🎙️ শুনেছি: _{transcript}_", parse_mode="Markdown")

    result = session.handle("speech", transcript)
    text = _format_response(result)
    kb = _get_keyboard(result["expect"], result.get("digits")) if not result.get("end") else None

    if result.get("end"):
        _sessions.pop(chat_id, None)
        _keypad_buffers.pop(chat_id, None)

    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=kb)


def start_telegram_bot():
    """Start the Telegram bot (blocking)."""
    if not TELEGRAM_AVAILABLE:
        raise RuntimeError(
            "python-telegram-bot is not installed. "
            "Run: pip install python-telegram-bot"
        )

    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError(
            "TELEGRAM_BOT_TOKEN environment variable not set. "
            "Get a token from @BotFather on Telegram."
        )

    db.init_db()

    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("end", cmd_end))
    app.add_handler(CallbackQueryHandler(handle_callback))
    app.add_handler(MessageHandler(filters.VOICE, handle_voice))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    log.info("🤖 upay Voice Guard Telegram Bot started!")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    start_telegram_bot()
