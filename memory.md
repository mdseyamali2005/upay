# Project Memory: 1uPay (উপায়)

## 📋 Overview
1uPay is a Bangla voice-powered payment assistant app. It consists of two main components:
1. **upay_demo** — Flutter mobile app (frontend) that handles UI, voice recording, and playback
2. **upay_voice_guard** — Python FastAPI backend (voice engine) that handles STT (Speech-to-Text), NLU (Natural Language Understanding via Gemini), TTS (Text-to-Speech via edge-tts), and conversation flow management

The app allows users to interact with a voice assistant in Bangla to perform payment-related tasks.

## 🛠️ Tech Stack & Architecture
- **Frontend**: Flutter (Dart) — `p:\1upay\upay_demo`
- **Backend**: Python 3.13 + FastAPI + Uvicorn — `p:\1upay\upay_voice_guard`
- **TTS Engine**: `edge-tts` (Microsoft Edge TTS, Bangla voice: `bn-BD-NabanitaNeural`)
- **STT**: Speech-to-text transcription module
- **NLU**: Google Gemini AI (via `google.genai` — new unified SDK)
- **Database**: SQLite (local, managed by `app/db.py`)
- **Key Libraries (Flutter)**: `just_audio`, `record`, `speech_to_text`, `http`, `firebase`
- **Key Libraries (Python)**: `fastapi`, `uvicorn`, `edge-tts`, `aiohttp`
- **Architecture**: Client-Server over LAN (phone ↔ PC on same Wi-Fi)

## 📂 Project Structure
```
p:\1upay\
├── upay_demo\                  # Flutter app
│   ├── lib\
│   │   ├── services\
│   │   │   └── agent_api.dart  # API client (LAN IP config here)
│   │   └── screens\
│   │       └── voice_agent_screen.dart
│   └── android\                # Android build config
│       ├── app\build.gradle.kts
│       ├── settings.gradle.kts
│       ├── gradle.properties
│       └── gradle\wrapper\gradle-wrapper.properties
├── upay_voice_guard\           # Python voice engine
│   └── app\
│       ├── main.py             # FastAPI server + /tts, /health, /session endpoints
│       ├── flow.py             # Conversation flow / session management
│       ├── stt.py              # Speech-to-text
│       ├── nlu.py              # Number/text processing utilities
│       ├── llm_nlu.py          # Gemini-based NLU
│       ├── speech_utils.py     # Bangla TTS text preparation
│       └── db.py               # SQLite database
├── jdk17\                      # Amazon Corretto JDK 17 (for Gradle builds)
└── memory.md                   # This file
```

## 🔧 Build Configuration (Android)
These were modified to resolve Java 26 + Gradle compatibility issues:
- **AGP**: `8.9.1` (in `settings.gradle.kts`)
- **Kotlin**: `2.0.21` (in `settings.gradle.kts`)
- **Gradle**: `8.11.1` (in `gradle-wrapper.properties`)
- **JDK**: Amazon Corretto 17 at `P:/1upay/jdk17/jdk17.0.20_12` (in `gradle.properties` → `org.gradle.java.home`)
- **Java Compatibility**: `VERSION_17` (in `build.gradle.kts`)
- **compileSdk**: `flutter.compileSdkVersion` (auto)
- **minSdk**: `max(flutter.minSdkVersion, 24)`

## 🌐 Network Configuration
- **Voice Guard Server**: Runs on `http://0.0.0.0:8000` (accessible from LAN)
- **PC Wi-Fi IP**: `172.20.10.2` (Mobile Hotspot)
- **Phone connects from**: USB reverse port `8000` & Hotspot IP `172.20.10.2` (Redmi Note 13)
- **agent_api.dart `_lan`**: Set to `http://172.20.10.2:8000` ✅ (Hotspot IP, updated 2026-10-07)
- **ADB Reverse**: `adb reverse tcp:8000 tcp:8000` enabled for USB tethering connection
- **Requirement**: Phone and PC must be on the same Wi-Fi/Hotspot or connected via USB

## 🚀 How to Run

### Voice Engine (PC):
```powershell
cd p:\1upay\upay_voice_guard
& "C:\Users\dell\AppData\Local\Programs\Python\Python313\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Flutter App (on device):
```powershell
cd p:\1upay\upay_demo
flutter run -d 31810ad8 --android-skip-build-dependency-validation
```

### Device Info:
- **Device**: Redmi Note 13 (23129RAA4G)
- **Device ID**: `31810ad8`
- **USB Debugging**: Enabled
- **Install via USB**: Enabled

## 🚀 Core Features
- [x] Voice recording and playback
- [x] Bangla Speech-to-Text (STT)
- [x] Bangla Text-to-Speech (TTS) via edge-tts
- [x] AI-powered NLU via Google Gemini
- [x] Conversational flow management (sessions)
- [x] User database with name TTS caching
- [x] Firebase integration (messaging/notifications)
- [ ] Production signing config (currently using debug keys)

## 📋 Task Board

### ⏳ Pending Tasks
(none)

### 🏃 In Progress Tasks
(none)

### ✅ Completed Tasks
- [x] **T25: Fix Send Money by Name (Rule-based NLU)**: Added `_extract_send_target()` function in `nlu.py` that extracts recipient name from Bangla voice input using regex patterns (e.g. "রাকিবকে ৫০০ টাকা সেন্ড কর" → extracts "রাকিব"). Also added missing send keywords (পাঠাও, পাঠান, pathao). Previously only worked with Gemini API key set. (Completed on: 2026-10-07)
- [x] **T26: Fix Address Book Display / IP Mismatch**: Updated `agent_api.dart` `_lan` from `192.168.137.1` → `172.20.10.2` (current hotspot IP). Address book contacts were in DB but app couldn't reach backend due to stale IP. (Completed on: 2026-10-07)
- [x] **T21: Address Book / Contacts Feature**: Added `contacts` table in backend, GET/POST `/contacts` endpoints, and `ContactsScreen` in Flutter under the "আরো" (More) tab. (Completed on: 2026-10-07)
- [x] **T22: Voice Send Money by Name**: Updated Gemini NLU `SYSTEM_PROMPT` to extract `target_name` for `send_money`. Updated `flow.py` to match the name against the user's contacts and initiate send money. (Completed on: 2026-10-07)
- [x] **T23: Send Money Cooldown (10 min)**: Added logic in `db.send_money` to block transactions to the same number if a `send_money` transaction occurred within the last 10 minutes. (Completed on: 2026-10-07)
- [x] **T24: Enforce Limit for Send Money**: Enforced `max_txn_limit` check in SQL inside `db.send_money` just like `cash_out`. (Completed on: 2026-10-07)
- [x] **T5: Impact Metrics Definition**: Defined 10 quantitative metrics (completion rate, time, errors, abandonment, confidence, risk precision/recall, FAQ deflection) + 4 qualitative metrics with measurement methods and targets. Documented in BUSINESS_IMPACT.md. (Completed on: 2026-10-07)
- [x] **T6: User Pilot / Validation Test**: Designed full pilot protocol — 15-20 users across 3 cohorts (older adults, low-literacy, control), 1-week duration, baseline vs Voice Guard comparison with paired t-test/McNemar/Wilcoxon analysis. Documented in BUSINESS_IMPACT.md. (Completed on: 2026-10-07)
- [x] **T7: Cost Estimation**: Per-transaction cost analysis (demo: ৳0.12, production: ৳0.89) vs call center (৳15-25), USSD (৳0.50-1.00). ROI: ৳189,100/month savings at 10K interactions. Documented in BUSINESS_IMPACT.md. (Completed on: 2026-10-07)
- [x] **T8: Target Persona Definition**: Defined 3 personas — Primary: Urban Low-Literacy MFS Customer (Faruk Mia, 45-65), Secondary: Rural Merchant/Agent (Rahima Begum, 30-50), Tertiary: Call Center Ops. Documented in BUSINESS_IMPACT.md. (Completed on: 2026-10-07)
- [x] **T9: Architecture Diagram**: Full integration boundary diagrams — system architecture (7-layer ASCII), data flow sequence (cash-out), security architecture (7 layers), conversation FSM, production migration table, and Mermaid integration diagram. Documented in ARCHITECTURE.md. (Completed on: 2026-10-07)
- [x] **T12: Latency/Throughput/Recovery Targets**: P95 latency targets (PIN ≤50ms, NLU ≤2s, full step ≤4s), throughput (100 concurrent sessions, 50 rps), 8 failure mode recovery specs (RTO ≤30s, RPO 0), horizontal scaling path, capacity planning table. Documented in PERFORMANCE_TARGETS.md. (Completed on: 2026-10-07)
- [x] **T19: UI/UX Flow Demo & Source Code Visibility**: Complete cash-out flow diagram (7 steps), alternative flows (balance, spending, FAQ, error handling, scam warning), full source code map (backend 10 files, tests 7 files, frontend, web UI, docs 8 files), demo instructions for browser + mobile + scam warning. Documented in UI_UX_FLOW.md. (Completed on: 2026-10-07)
- [x] **T20: Comparison Table vs Existing Solutions**: 18-feature comparison table (Voice Guard vs Traditional IVR vs App vs Call Center), 5 key differentiators (keypad-only security, personalized risk scoring, dialect-aware NLU, voice spending insights, AI safety guardrails), usage scenario recommendation table. Documented in COMPARISON.md. (Completed on: 2026-10-07)
- [x] **T4: Personalized Risk Scoring (Fraud Detection)**: Replaced fixed half-balance heuristic with personalized behavioral risk signals. Fixed failing tests in the test suite. (Completed on: 2026-10-07)
- [x] **T10: Durable Session Storage**: Moved sessions from in-memory to shared durable store (e.g. SQLite/Redis); tested multi-instance capability. (Completed on: 2026-10-07)
- [x] **T15: Prompt Injection & LLM Safety**: Contained prompt injection / wrong LLM intent before financial actions, sanitizing input before sending to LLM. (Completed on: 2026-10-07)
- [x] **T16: Privacy & Explainability Statement**: Added explainability by detailing exactly why a risk warning fired. (Completed on: 2026-10-07)
- [x] **T18: Scam Warning Demo**: Made scam-warning demo reachable under transaction limit. (Completed on: 2026-10-07)
- [x] **T1: Bangla/Banglish Intent Dataset & Accuracy Report**: 85-sample dataset across 17 categories, eval harness produces confusion matrix, per-intent P/R/F1. Combined accuracy: 98.8%. (Completed on: 2026-10-07)
- [x] **T2: Rule-based NLU vs Gemini Comparison**: Side-by-side metrics in eval report. Rule: 82.4%, Gemini alone: 9.4%, Combined: 98.8%. (Completed on: 2026-10-07)
- [x] **T3: Dialect/Noise/ASR Robustness Testing**: Dataset covers 6 dialect variants, ASR errors, code-switching, misspellings. All pass in combined NLU. (Completed on: 2026-10-07)
- [x] **T11: Idempotency & Durable Transactions**: SecurityManager with idempotency key cache + TTL, integrated in /session/{sid}/input endpoint. (Completed on: 2026-10-07)
- [x] **T13: Authenticated Sessions & API Protection**: Session tokens (SHA-256 hashed), CORS restricted to LAN subnets, X-Session-Token header verification. (Completed on: 2026-10-07)
- [x] **T14: Rate Limiting & Replay Protection**: Per-IP rate limiting (30 req/min), lockout (300s), nonce-based replay protection, full audit log. (Completed on: 2026-10-07)
- [x] **T17: Robustness Test Suite**: 8 test classes covering duplicate confirm, concurrent cash-out, disconnect/restart, session end, amount edge cases, PIN lockout persistence, rapid-fire, FAQ fallback. (Completed on: 2026-10-07)
- [x] **Deploy and Verify App on New Mobile Hotspot / USB**: Updated network configuration to `172.20.10.2` (Mobile Hotspot), enabled `adb reverse tcp:8000 tcp:8000` for high-speed USB reverse forwarding, installed and launched the latest build (`app-debug.apk`) on connected Redmi Note 13 (`31810ad8`). Both `/health` and `/session/start` endpoints verified reachable and functional from device over USB and hotspot. (Completed on: 2026-10-07)
- [x] **Fix Voice Agent Transaction Sync**: Transactions made via voice agent (cash_out) are recorded in backend SQLite but not reflected in Flutter app's history screen or balance. Need to: (1) add `/user/info` API endpoint returning balance + transactions, (2) sync Flutter app data after voice agent session, (3) make history screen and balance displays dynamic. (Completed on: 2026-10-06)
- [x] **Fix agent_api.dart IP**: Updated `_lan` from `192.168.137.1` → `10.100.93.121` (current Wi-Fi IP). (Completed on: 2026-10-06)
- [x] **Migrate google.generativeai → google.genai**: Migrated `llm_nlu.py` from deprecated `google.generativeai` (global configure + GenerativeModel) to new `google.genai` (Client-based) SDK. Updated `requirements.txt`. (Completed on: 2026-10-06)
- [x] **Firebase task removed**: No Firebase code exists in the project — task was stale/invalid. (Completed on: 2026-10-06)
- [x] **Voice Engine TTS Streaming**: TTS endpoint now uses `StreamingResponse` for chunked audio delivery. (Completed on: 2026-10-06)
- [x] **Flutter App Build & Deploy**: Resolved Java 26 + Gradle/AGP compatibility issues. App successfully built and deployed to Redmi Note 13. (Completed on: 2026-10-06)
- [x] **JDK 17 Setup**: Downloaded and configured Amazon Corretto JDK 17 to bypass Java 26 jlink crash. (Completed on: 2026-10-06)
- [x] **Android Build Config Fix**: Updated AGP (8.9.1), Gradle (8.11.1), Kotlin (2.0.21) for dependency compatibility. (Completed on: 2026-10-06)
- [x] **edge-tts Installation**: Installed edge-tts package to fix TTS 500 Internal Server Error. (Completed on: 2026-10-06)
- [x] **Voice Guard Server Setup**: Started uvicorn server on port 8000. (Completed on: 2026-10-06)
- [x] **SDK Tools Auto-Install**: Android SDK Build-Tools 35 and CMake 3.22.1 auto-installed during build. (Completed on: 2026-10-06)

## 📝 Key Decisions & Notes
- **JDK 17 over Java 26 (2026-10-06)**: Java 26 (system default) causes `jlink.exe` crash with Android Gradle Plugin. Solution: Downloaded JDK 17 separately and configured `org.gradle.java.home` in `gradle.properties`.
- **AGP 8.9.1 chosen (2026-10-06)**: Dependencies (`androidx.browser:1.9.0`, `androidx.core:1.17.0`) require minimum AGP 8.9.1. Earlier attempt with AGP 8.5.2 failed.
- **`--android-skip-build-dependency-validation` flag (2026-10-06)**: Used to bypass Flutter's strict Gradle/AGP version validation that conflicts with the custom configuration.
- **Build changes are build-system only (2026-10-06)**: No app code or features were modified. All changes were in Gradle/Android build configuration files only.
- **edge-tts was missing (2026-10-06)**: The TTS endpoint was returning 500 errors because `edge-tts` package was not installed on the new device. Fixed by `pip install edge-tts`.
