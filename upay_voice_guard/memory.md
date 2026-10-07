# Project Memory: upay Voice Guard

## 📋 Overview
Voice-based mobile banking agent for upay (Bangladesh). Allows users to cash out money, check balance, and view spending via voice calls. Includes web browser UI, Telegram bot, WhatsApp bot, and a Flutter demo app.

## 🛠️ Tech Stack & Architecture
- **Backend**: Python FastAPI (app/main.py)
- **Frontend**: HTML/CSS/JS (app/static/)
- **NLU**: Rule-based + Gemini LLM (app/nlu.py, app/llm_nlu.py)
- **TTS**: Browser speechSynthesis (frontend), gTTS (backend)
- **STT**: Browser Web Speech API + server-side Whisper/Google Cloud
- **Database**: SQLite (app/db.py)
- **Bots**: Telegram (app/telegram_bot.py), WhatsApp (app/whatsapp_bot.py)
- **Flutter App**: upay_demo/ (Android demo with voice agent screen)
- **Architecture Style**: State machine conversation flow (app/flow.py)

## 🚀 Core Features
- [x] PIN-based authentication with lockout
- [x] Cash out with agent number + amount + confirmation
- [x] Balance inquiry
- [x] Spending summary (this/last month)
- [x] Risk warning for new numbers + high amounts
- [x] LLM-powered intent parsing + FAQ
- [x] Telegram & WhatsApp bot interfaces

## 📋 Task Board

### ⏳ Pending Tasks

### 🏃 In Progress Tasks

### ✅ Completed Tasks
- [x] **Fix Voice Problems**: Fixed 3 voice quality issues (English name spelling, phone number readability, robotic voice). Added edge-tts, speakable() helper, rewrote prompts to কথ্য Bangla. (Completed on: 2026-10-06)
- [x] **Replace Voice Agent Logo**: Replaced the agent_ai.jpg in the Flutter demo app with the new Friendly Voice Agent Logo.png. (Completed on: 2026-10-06)

## 📝 Key Decisions & Notes
- **PIN/Limit Logic**: Must NOT be changed (security critical)
- **Scam Warning**: Must NOT be changed
- **Existing Tests**: Must NOT break
- **Money moves only in**: app/db.py::cash_out
- **LLM only picks intents**: Never moves money
