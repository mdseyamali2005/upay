# 1uPay (উপায়) Voice Guard - Hackathon Project Documentation

## 🚀 Project Overview
**1uPay Voice Guard** is an innovative, voice-first payment assistant designed to make digital financial services accessible, intuitive, and hands-free. Built specifically for the **Upay** ecosystem, this project bridges the gap for users who may struggle with complex UI navigation, allowing them to perform transactions simply by speaking in **Bengali**.

The system consists of a **Flutter mobile application** (Frontend) and a **Python FastAPI AI Voice Engine** (Backend). 

---

## 🛠️ Architecture & Tech Stack

### 📱 Frontend (Mobile App)
- **Framework**: Flutter (Dart)
- **Audio Handling**: `just_audio` (playback) & `record` (voice capture)
- **Speech-to-Text**: On-device Speech-to-Text with Google Speech API fallback.
- **Key Feature**: The app dynamically discovers the local backend server via LAN scanning, minimizing connection setup time.

### 🧠 Backend (AI Voice Engine)
- **Framework**: FastAPI (Python 3.13) via Uvicorn.
- **NLU (Natural Language Understanding)**: Google Gemini 2.0 Flash (`google-genai`). It parses Bengali speech into structured intents (e.g., `cash_out`, `balance`, `send_money`, `faq`).
- **TTS (Text-to-Speech)**: `edge-tts` utilizing the Microsoft Edge Neural Voice (`bn-BD-NabanitaNeural`) for natural-sounding Bengali responses.
- **Database**: SQLite (managed via `db.py`) for user sessions, limits, and mock transactions.
- **Audio Streaming**: `StreamingResponse` for chunk-by-chunk real-time audio playback, significantly reducing TTS delay to under 2-3 seconds.

---

## ⚙️ How It Works (The Workflow)

1. **Trigger**: User taps the Agent AI Microphone in the Upay App and speaks in Bengali (e.g., *"আমি ক্যাশ আউট করতে চাই"*).
2. **STT Processing**: The phone captures the audio and uses the Google Speech-to-Text engine to transcribe the voice to Bengali text.
3. **Intent Parsing (NLU)**: The text is sent to the FastAPI backend. Gemini 2.0 Flash analyzes the text and extracts the exact intent and parameters.
4. **Action & Response Logic**: The session manager (`flow.py`) determines the next step. If a PIN is needed, it prompts the user. If an FAQ is asked, it queries the Gemini-powered FAQ Knowledge Base.
5. **TTS Generation**: The response text (e.g., *"কত টাকা ক্যাশ আউট করবেন?"*) is converted to speech via `edge-tts` and streamed directly back to the Flutter app.
6. **Execution**: The Flutter app plays the audio and dynamically updates the UI to show a Keypad or Microphone based on what the agent expects next.

---

## 💡 Key Features for the Hackathon

- **Ultra-Fast Voice Response**: Optimized TTS streaming reduces response latency, making conversations feel natural and instantaneous.
- **Contextual Bengali AI**: Powered by Gemini 2.0, the NLU engine understands complex Bengali phrases, slang, and contextual money markers.
- **Smart FAQ Assistant**: Users can ask anything about Upay's charges or rules, and the AI answers based on a strict semantic knowledge base.
- **Adaptive UI**: The app screen instantly adapts between Voice Mode and Keypad Mode depending on the required input (e.g., asking for a secure 4-digit PIN via keypad instead of voice).
- **Network Resilient**: Automatic LAN discovery ensures the phone finds the backend engine even if IP addresses change.

---

## 🔧 Hackathon Setup & Usage Guide

If demonstrating on a new Wi-Fi network during the hackathon:
1. Connect both the **Laptop** and the **Mobile Phone** to the **same Wi-Fi network**.
2. Run `ipconfig` on the laptop to find the new IPv4 Address.
3. Start the backend: `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`
4. The mobile app has an auto-discovery feature, but for instant connection, update `_lan` in `agent_api.dart` to the new IP and restart the app.

---
*Built with ❤️ for inclusive digital finance.*
