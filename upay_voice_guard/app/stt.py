"""Speech-to-Text backends (optional).
Primary STT is handled by the browser's Web Speech API (no API key needed).
This module adds server-side STT for uploaded audio files (e.g. from Telegram voice notes).

Supported backends:
  1. OpenAI Whisper API  — set OPENAI_API_KEY env var
  2. Google Cloud STT    — set GOOGLE_APPLICATION_CREDENTIALS env var
  3. Fallback            — returns empty string (browser handles STT)
"""
import os
import io
import logging

log = logging.getLogger(__name__)


def _whisper_transcribe(audio_bytes: bytes, language: str = "bn") -> str:
    """Transcribe using OpenAI Whisper API."""
    try:
        import httpx
        api_key = os.environ["OPENAI_API_KEY"]
        resp = httpx.post(
            "https://api.openai.com/v1/audio/transcriptions",
            headers={"Authorization": f"Bearer {api_key}"},
            files={"file": ("audio.ogg", io.BytesIO(audio_bytes), "audio/ogg")},
            data={"model": "whisper-1", "language": language},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json().get("text", "").strip()
    except Exception as e:
        log.warning("Whisper STT failed: %s", e)
        return ""


def _google_stt_transcribe(audio_bytes: bytes, language: str = "bn-BD") -> str:
    """Transcribe using Google Cloud Speech-to-Text v1."""
    try:
        from google.cloud import speech
        client = speech.SpeechClient()
        audio = speech.RecognitionAudio(content=audio_bytes)
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.OGG_OPUS,
            sample_rate_hertz=48000,
            language_code=language,
            enable_automatic_punctuation=True,
        )
        response = client.recognize(config=config, audio=audio)
        return " ".join(
            r.alternatives[0].transcript for r in response.results
        ).strip()
    except Exception as e:
        log.warning("Google Cloud STT failed: %s", e)
        return ""


def transcribe(audio_bytes: bytes, language: str = "bn") -> str:
    """Transcribe audio bytes to text using the best available backend.
    Returns empty string if no backend is configured or transcription fails."""
    if os.environ.get("OPENAI_API_KEY"):
        result = _whisper_transcribe(audio_bytes, language)
        if result:
            return result

    if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        lang_code = "bn-BD" if language == "bn" else language
        result = _google_stt_transcribe(audio_bytes, lang_code)
        if result:
            return result

    log.info("No STT backend configured; returning empty string.")
    return ""
