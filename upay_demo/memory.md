# Project Memory: upay_demo & upay_voice_guard

## 📋 Overview
**uPay Voice Guard Integration** is a dual-component project comprising a **Flutter mobile/web application (`upay_demo`)** and a **FastAPI Python backend (`upay_voice_guard`)**. The primary objective is to implement an intelligent voice agent that can process voice commands, verify transactions, interact in Bengali via STT (Speech-to-Text) and TTS (Text-to-Speech), and provide a dynamic, Siri-like interactive voice experience for financial transactions.

## 🛠️ Tech Stack & Architecture
- **Frontend**: Flutter (Dart) for Cross-Platform App (Android/iOS/Web).
- **Backend / API**: FastAPI (Python), Uvicorn.
- **Key Libraries (App)**: `speech_to_text`, `record` (for audio capture), `just_audio` (for audio playback), `audio_session`.
- **Key Libraries (Backend)**: `gTTS` (Google Text-to-Speech), `google-generativeai` (for LLM intent parsing).
- **Architecture Style**: Client-Server architecture. The Flutter app captures voice and sends it to the Python backend. The backend processes the intent and sends back a response and synthesized voice (TTS).

## 🚀 Core Features
- [x] On-Device Speech Recognition (STT) for fast and seamless transcription.
- [x] Backend Text-to-Speech (TTS) integration using gTTS for Bengali voice replies.
- [x] Dynamic Siri-like Voice Animation that reacts to microphone input volume.
- [x] Financial Transaction Voice Flow (intent recognition for tasks like "Send Money").
- [ ] WhatsApp Bot integration (Backend setup exists).

## 📋 Task Board

### ⏳ Pending Tasks
- [ ] **WhatsApp Bot Configuration**: Setup API keys for the backend WhatsApp integration.
- [ ] **Deploy Backend to Production**: Host the FastAPI server on a cloud provider (e.g., Render, Railway) with proper API keys.

### 🏃 In Progress Tasks
- [/] **Testing Voice Engine Flow**: Validating the end-to-end voice loop (Speech -> Backend -> TTS -> Playback).

### ✅ Completed Tasks
- [x] **Integrate Local TTS Engine (gTTS)**: Added `/tts` endpoint in FastAPI backend to resolve the missing voice response issue (2026-10-05).
- [x] **Fix Mic Loop Bug**: Solved issue where partial speech wasn't sent when the user stopped speaking, causing infinite on/off mic loops (2026-10-05).
- [x] **Automate Instruction Execution**: Configured the microphone to properly use Android's built-in fast speech-to-text (2026-10-05).
- [x] **Siri-like Voice Animation**: Implemented a dynamic wave animation around the mic that reacts to voice volume (2026-10-05).

## 📝 Key Decisions & Notes
- **Voice Engine Feasibility**: High-quality AI parsing requires a backend server. We use local Android STT for input speed, and the backend processes intent and generates TTS audio.
- **Backend Communication Fallback**: The app's `AgentApi` probes multiple addresses to find the server (`127.0.0.1:8000`, `192.168.x.x:8000`, and a live URL).

---

## 💻 How to Run Manually (Local & Network)

### 1. Run the Backend (Python)
The backend must be running to process intents and generate TTS.
1. Open a terminal and navigate to the backend folder:
   ```bash
   cd e:\upay_agent\upay_voice_guard
   ```
2. Start the FastAPI server:
   ```bash
   python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

### 2. Run the Frontend (Flutter App)
#### Scenario A: Running on a USB-Connected Phone (Localhost)
If your phone is connected via USB, it cannot natively access `127.0.0.1:8000` of your PC without port forwarding.
1. Open a new terminal and run ADB reverse to forward the port:
   ```bash
   adb reverse tcp:8000 tcp:8000
   ```
2. Run the Flutter app:
   ```bash
   cd e:\1upay\upay_demo
   flutter run
   ```

#### Scenario B: Running on Another Device or Wi-Fi Network
If you want to run the app on a device that is NOT connected via USB, or share the backend across your local Wi-Fi:
1. Ensure both the PC (running the backend) and the mobile device are connected to the **same Wi-Fi network**.
2. Find your PC's local IP address (e.g., `192.168.0.100`) by running `ipconfig` in the Windows terminal (look for IPv4 Address).
3. The Flutter app's `AgentApi` (`lib/services/agent_api.dart`) is already programmed to scan the Wi-Fi network (`_scanLan()`) and find the server running on port `8000`. 
4. Just make sure your Windows Firewall is not blocking port `8000`. If it is, allow Python/Uvicorn through the firewall.
5. Install the APK on the phone or run `flutter run` via wireless debugging.
