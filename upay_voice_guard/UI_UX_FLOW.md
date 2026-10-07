# T19: UI/UX Flow Demo & Source Code Guide

## User Flow: Complete Cash-Out Transaction

### Flow Diagram

```
┌─────────────────────────────┐
│     LAUNCH VOICE AGENT      │
│  User taps microphone icon  │
│  in Flutter app              │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│     STEP 1: PIN ENTRY       │
│                             │
│  🔊 "আপনার ৪ ডিজিটের পিন,  │
│     কীপ্যাডে দিন।"          │
│                             │
│  📱 Keypad appears          │
│  ⌨️  User enters: 1234      │
│                             │
│  ✅ PIN verified             │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│     STEP 2: GREETING        │
│                             │
│  🔊 "হ্যালো সেয়াম আলী     │
│     স্যার, আপনাকে কীভাবে    │
│     সাহায্য করতে পারি?"      │
│                             │
│  🎤 User says: "ক্যাশ আউট   │
│     করতে চাই"               │
│                             │
│  🤖 NLU → cash_out          │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│   STEP 3: AGENT NUMBER      │
│                             │
│  🔊 "এজেন্টের ১১ ডিজিটের   │
│     মোবাইল নম্বর, কীপ্যাডে  │
│     দিন।"                   │
│                             │
│  📱 Keypad: 11-digit entry  │
│  ⌨️  User enters: 01811111111│
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│   STEP 4: NUMBER CONFIRM    │
│                             │
│  🔊 "আমি আবার কনফার্ম      │
│     করছি, নম্বরটি           │
│     01811111111। ঠিক থাকলে  │
│     'হ্যাঁ' বা 'না' বলুন।"  │
│                             │
│  🎤 User says: "হ্যাঁ"      │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│     STEP 5: AMOUNT          │
│                             │
│  🔊 "কত টাকা ক্যাশ আউট     │
│     করবেন? অ্যামাউন্ট       │
│     কীপ্যাডে দিন।"          │
│                             │
│  📱 Keypad: amount entry    │
│  ⌨️  User enters: 4000      │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│   STEP 5a: RISK CHECK       │
│   (only if score ≥ 0.35)    │
│                             │
│  🔊 "সতর্কতা (ঝুঁকি স্কোর: │
│     55%): নতুন নম্বর —      │
│     আগে কখনো এই নম্বরে     │
│     লেনদেন হয়নি।            │
│     ব্যালেন্সের 80% — প্রায় │
│     সব টাকা তোলা হচ্ছে।    │
│     কেউ কি ফোনে আপনাকে    │
│     টাকা দিতে চাপ দিচ্ছে?"  │
│                             │
│  🎤 User says: "হ্যাঁ"      │
│  (confirms own decision)     │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│   STEP 6: FINAL CONFIRM     │
│                             │
│  🔊 "আপনি কি 01811111111   │
│     নম্বরে, ৪০০০ টাকা ক্যাশ │
│     আউট করতে চান? কনফার্ম  │
│     করতে 'হ্যাঁ' বলুন।"     │
│                             │
│  🎤 User says: "হ্যাঁ"      │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│     STEP 7: SUCCESS         │
│                             │
│  🔊 "সফল হয়েছে। ৪০০০ টাকা │
│     ক্যাশ আউট করা হয়েছে।   │
│     নতুন ব্যালেন্স ২১০০০    │
│     টাকা। আর কিছু করতে     │
│     পারি?"                  │
│                             │
│  🎤 User says: "না, ধন্যবাদ"│
│                             │
│  🔊 "ধন্যবাদ। আপনার দিনটি  │
│     শুভ হোক।"               │
└─────────────────────────────┘
```

## Alternative Flows

### Balance Check
```
User: "ব্যালেন্স জানতে চাই"
  → NLU: balance
  → 🔊 "আপনার ব্যালেন্স ২৫০০০ টাকা। আর কিছু করতে পারি?"
```

### Spending Summary
```
User: "এই মাসে কত খরচ হয়েছে?"
  → NLU: spending (month: this)
  → 🔊 "অক্টোবর মাসে আপনার মোট খরচ ৩৫০০ টাকা,
     সবচেয়ে বেশি খরচ হয়েছে ক্যাশ আউট এ, ২০০০ টাকা।
     আর কিছু করতে পারি?"
```

### FAQ Query
```
User: "ক্যাশ আউটে কত চার্জ লাগে?"
  → NLU: faq
  → Gemini + Knowledge Base lookup
  → 🔊 "এজেন্ট থেকে ক্যাশ আউটে ১.৮৫% চার্জ প্রযোজ্য,
     সর্বনিম্ন ৫ টাকা। আর কিছু করতে পারি?"
```

### Error Handling: Wrong Number
```
User enters: 0181111     (7 digits)
  → 🔊 "নম্বরটি ১১ ডিজিটের হতে হবে, আপনি ৭ ডিজিট দিয়েছেন।
     আবার ট্রাই করুন। এজেন্টের ১১ ডিজিটের মোবাইল নম্বর, কীপ্যাডে দিন।"
  (Up to 3 retries before auto-cancel)
```

### Scam Warning Demo
```
Scenario: First-time user, new number, large amount (4000 of 5000 balance)
  → Risk signals: [new number (0.30), balance ratio 80% (0.25)] = 0.55
  → 🔊 "সতর্কতা (ঝুঁকি স্কোর: 55%): নতুন নম্বর — আগে কখনো
     এই নম্বরে লেনদেন হয়নি। ব্যালেন্সের 80% — প্রায় সব টাকা
     তোলা হচ্ছে। কেউ কি ফোনে আপনাকে টাকা দিতে চাপ দিচ্ছে?"

  User says "না" → Transaction cancelled (safety preserved)
  User says "হ্যাঁ" → Proceeds to final confirmation
```

## Source Code Map

### Backend (Python — `upay_voice_guard/`)

| File | Lines | Purpose |
|------|-------|---------|
| [`app/main.py`](app/main.py) | 226 | FastAPI server, endpoints, middleware |
| [`app/flow.py`](app/flow.py) | 226 | Conversation state machine (FSM) |
| [`app/nlu.py`](app/nlu.py) | 203 | Rule-based NLU (Bangla/Banglish/dialects) |
| [`app/llm_nlu.py`](app/llm_nlu.py) | 259 | Gemini LLM NLU + prompt injection defense |
| [`app/db.py`](app/db.py) | 265 | SQLite database + risk scoring engine |
| [`app/security.py`](app/security.py) | 170 | Session auth, rate limiting, audit logging |
| [`app/speech_utils.py`](app/speech_utils.py) | ~120 | Bangla TTS text preparation |
| [`app/stt.py`](app/stt.py) | ~70 | Speech-to-text interface |
| [`app/whatsapp_bot.py`](app/whatsapp_bot.py) | ~450 | WhatsApp Cloud API integration |
| [`app/telegram_bot.py`](app/telegram_bot.py) | ~350 | Telegram bot integration |

### Tests (Python — `upay_voice_guard/tests/`)

| File | Tests | Purpose |
|------|-------|---------|
| [`tests/test_flow.py`](tests/test_flow.py) | ~15 | Core flow state transitions |
| [`tests/test_robustness.py`](tests/test_robustness.py) | ~30 | Duplicate confirm, concurrency, edge cases |
| [`tests/test_security.py`](tests/test_security.py) | ~25 | Auth, rate limiting, replay, injection |
| [`tests/test_speech_utils.py`](tests/test_speech_utils.py) | ~8 | TTS text normalization |
| [`tests/eval_nlu.py`](tests/eval_nlu.py) | 85-sample | NLU accuracy evaluation harness |
| [`tests/intent_dataset.json`](tests/intent_dataset.json) | 85 entries | Bangla/Banglish intent dataset |

### Frontend (Flutter — `upay_demo/`)

| File | Purpose |
|------|---------|
| `lib/services/agent_api.dart` | REST API client (LAN connection) |
| `lib/screens/voice_agent_screen.dart` | Voice agent UI screen |

### Web UI (Static — `app/static/`)

| File | Purpose |
|------|---------|
| `app/static/index.html` | Browser-based demo interface |
| `app/static/style.css` | Styling (dark theme) |
| `app/static/app.js` | Client-side JS (Web Speech API + keypad) |

### Documentation

| File | Purpose |
|------|---------|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | System architecture diagrams (T9) |
| [`BUSINESS_IMPACT.md`](BUSINESS_IMPACT.md) | Impact metrics, personas, cost (T5-T8) |
| [`PERFORMANCE_TARGETS.md`](PERFORMANCE_TARGETS.md) | Latency/throughput/recovery (T12) |
| [`PRIVACY_EXPLAINABILITY.md`](PRIVACY_EXPLAINABILITY.md) | Privacy, synthetic data, explainability (T16) |
| [`COMPARISON.md`](COMPARISON.md) | vs IVR / app / call center (T20) |
| [`nlu_evaluation_report.md`](nlu_evaluation_report.md) | NLU accuracy report (T1-T3) |
| [`README.md`](README.md) | Project overview |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Deployment guide |

## Demo Instructions

### Browser Demo (PC)

1. Start the server:
   ```powershell
   cd p:\1upay\upay_voice_guard
   & "C:\Users\dell\AppData\Local\Programs\Python\Python313\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

2. Open browser: `http://localhost:8000`

3. Demo flow:
   - Enter PIN: `1234`
   - Say or type: "ক্যাশ আউট করতে চাই"
   - Enter agent number: `01811111111` (new number → triggers scam warning)
   - Confirm number: "হ্যাঁ"
   - Enter amount: `4000` (high balance ratio → risk warning appears)
   - Acknowledge risk warning: "হ্যাঁ"
   - Confirm transaction: "হ্যাঁ"

### Mobile Demo (Flutter)

1. Start server (same as above)
2. Deploy app:
   ```powershell
   cd p:\1upay\upay_demo
   flutter run -d 31810ad8 --android-skip-build-dependency-validation
   ```
3. Tap the voice agent button in the app to start

### Scam Warning Demo (T18)

To reliably trigger the scam warning under the default 5,000 TK limit:

1. Start a new session (PIN: 1234)
2. Say "ক্যাশ আউট"
3. Enter a **new number** (not 01811111111 or 01911111111): e.g., `01712345678`
4. Confirm the number
5. Enter amount: `4000` (4000 / 25000 = 16%, but new number alone = 0.30 weight)

**Expected**: Risk score ≥ 0.35 → scam warning with explanation:
- "নতুন নম্বর — আগে কখনো এই নম্বরে লেনদেন হয়নি"
- Additional factors if balance ratio is high

For even higher risk score, do 2 cash-outs first, then the 3rd will trigger frequency signals too.
