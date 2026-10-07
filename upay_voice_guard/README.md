# upay Voice Guard

Voice-call cash-out agent for the upay hackathon (Track 03 — Customer Innovation & Financial Independence).  
**Everything is fake data**: fake user, fake PIN `1234`, mock ledger. Never put a real PIN, number or account here.

## 🎯 Features

- **PIN authentication** with 3-try lockout (PBKDF2-SHA256 hashing)
- **Cash-out flow** with full confirmation cycle + voice readback
- **Per-transaction limit** (set via website/app, enforced in SQL)
- **T4: Personalized risk scoring** — 5 behavioral signals replace fixed heuristic
- **T16: Explainable scam warnings** — user sees WHY in Bangla
- **Balance query** & **Spending summary** (by month, top category)
- **LLM-powered NLU** (Gemini 2.0 Flash) — 98.8% accuracy on 85-sample dataset
- **T15: AI Safety** — prompt injection detection, input sanitization, output validation
- **T13: Authenticated sessions** — SHA-256 hashed tokens
- **T14: Rate limiting** — 30 req/min per IP + lockout + replay protection + audit log
- **T11: Idempotency keys** — prevents duplicate transactions
- **T10: Durable session storage** — pluggable backends (Memory/SQLite/Redis)
- **Browser Call Screen** — dark-mode glassmorphism UI with Bangla TTS
- **Telegram Bot** — inline Bangla keypads, voice note STT
- **WhatsApp Bot** — interactive buttons/lists, voice note STT
- **Cloud-ready** — Dockerfile, Render & Railway configs

## Design Rules

- **Speech** = intent, questions, yes/no. **Keypad** = PIN, agent number, amount.
- The agent reads the number back; the user confirms by voice (or 1 = yes, 2 = no).
- Per-transaction limit is set via website/app (`PUT /limit`); voice cannot change it.
- Money moves only in `app/db.py::cash_out` — the LLM only picks intents.
- **T4**: Personalized risk scoring replaces the fixed half-balance heuristic with 5 behavioral signals.
- 3 wrong PINs → lock.

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture, data flow, security layers (T9) |
| [BUSINESS_IMPACT.md](BUSINESS_IMPACT.md) | Target personas, impact metrics, pilot protocol, cost estimation (T5-T8) |
| [PERFORMANCE_TARGETS.md](PERFORMANCE_TARGETS.md) | Latency, throughput, recovery targets + scaling path (T12) |
| [PRIVACY_EXPLAINABILITY.md](PRIVACY_EXPLAINABILITY.md) | Privacy statement, synthetic data, explainability (T16) |
| [COMPARISON.md](COMPARISON.md) | Voice Guard vs IVR/app/call center comparison (T20) |
| [UI_UX_FLOW.md](UI_UX_FLOW.md) | User flow diagrams, demo instructions, source code map (T19) |
| [nlu_evaluation_report.md](nlu_evaluation_report.md) | NLU accuracy: 98.8% combined, per-intent P/R/F1 (T1-T3) |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Cloud deployment guide |

## 🚀 Run Locally

```bash
pip install -r requirements.txt
python -m pytest tests/ -v        # ~70+ tests
python cli.py                     # terminal demo (PIN: 1234)
uvicorn app.main:app --reload     # web UI + API at http://127.0.0.1:8000
```

**Session store backends (T10):**
```bash
# Default: in-memory (fast, sessions lost on restart)
uvicorn app.main:app --reload

# SQLite (durable, single-instance)
VG_SESSION_STORE=sqlite uvicorn app.main:app --reload

# Redis (durable, multi-instance production)
VG_SESSION_STORE=redis REDIS_URL=redis://localhost:6379/0 uvicorn app.main:app --reload
```

**Optional bots:**
```bash
# Telegram bot (standalone polling)
TELEGRAM_BOT_TOKEN=your_token python -m app.telegram_bot

# WhatsApp bot — auto-mounts at /whatsapp/webhook when env vars are set
# Set WHATSAPP_TOKEN, WHATSAPP_PHONE_ID, WHATSAPP_VERIFY_TOKEN
```

## ☁️ Cloud Deployment

See **[DEPLOYMENT.md](DEPLOYMENT.md)** for full Render & Railway instructions.

## 🔌 API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Browser call screen UI |
| `/session/start` | POST | Start a new voice session |
| `/session/{id}/input` | POST | Send `{kind, value}` → next prompt |
| `/limit` | GET/PUT | Read/set transaction limit |
| `/user/info` | GET | User balance + transaction history |
| `/stt` | POST | Server-side speech-to-text |
| `/tts` | POST | Bangla text-to-speech (streaming) |
| `/health` | GET | Health check (for cloud platforms) |
| `/audit` | GET | Security audit log (T14) |
| `/whatsapp/webhook` | GET/POST | WhatsApp webhook (verify + messages) |

## 🧪 Demo

- **PIN**: `1234`
- **Demo user**: MD. SEYAM ALI, balance 25,000 TK, limit 5,000 TK
- **Known agent numbers**: `01811111111`, `01911111111`
- **Scam warning demo**: PIN 1234 → "ক্যাশ আউট" → `01712345678` (new) → "হ্যাঁ" → `4500` (with low balance) → risk warning appears
- **Normal flow**: PIN 1234 → "ক্যাশ আউট" → `01811111111` → "হ্যাঁ" → `3000` → "হ্যাঁ"

## 🧪 Test Suite

```bash
python -m pytest tests/ -v
```

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `test_flow.py` | ~15 | Core conversation flow |
| `test_robustness.py` | ~30 | Duplicates, concurrency, edge cases (T17) |
| `test_security.py` | ~25 | Auth, rate limiting, replay, injection (T13/T14/T15) |
| `test_session_store.py` | ~20 | Session store backends + scam warning (T10/T18) |
| `test_speech_utils.py` | ~8 | TTS text normalization |
| `eval_nlu.py` | 85 samples | NLU accuracy evaluation (T1-T3) |

