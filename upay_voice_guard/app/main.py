"""FastAPI wrapper. Run: uvicorn app.main:app --reload"""
import logging
import os
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, UploadFile, File, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import io
import asyncio
try:
    import edge_tts
except ImportError:
    edge_tts = None

from . import db
from .flow import Session
from .stt import transcribe
from .speech_utils import speakable
from .security import security, ALLOWED_ORIGINS
from .session_store import get_session_store

log = logging.getLogger(__name__)

STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    # T10: Initialize durable session store
    store = get_session_store()
    log.info("Session store initialized: %s", type(store).__name__)
    yield


app = FastAPI(title="upay Voice Guard (mock)", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1|172\.20\.10\.\d+|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*", "X-Session-Token", "X-Nonce", "X-Idempotency-Key"],
)


# ── Rate Limiting Middleware ──
@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    """T14: Per-IP rate limiting with lockout."""
    # Skip rate limiting for health checks
    if request.url.path in ("/health", "/", "/docs", "/openapi.json"):
        return await call_next(request)

    client_ip = request.client.host if request.client else "unknown"
    allowed, reason = security.check_rate_limit(client_ip)
    if not allowed:
        security.audit("RATE_LIMITED", client_ip=client_ip, path=request.url.path)
        return JSONResponse(status_code=429, content={"detail": reason})

    return await call_next(request)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# ── WhatsApp Bot (auto-mount if configured) ──
try:
    from .whatsapp_bot import router as wa_router, is_configured as wa_configured
    app.include_router(wa_router)
    if wa_configured():
        log.info("✅ WhatsApp Bot webhook mounted at /whatsapp/webhook")
    else:
        log.info("ℹ️ WhatsApp router mounted but not configured (set WHATSAPP_TOKEN & WHATSAPP_PHONE_ID)")
except Exception as e:
    log.warning("WhatsApp bot not loaded: %s", e)

# T10: Pluggable session store (set VG_SESSION_STORE=sqlite or redis for durability)
# Legacy dict kept as fast-path cache; store is the source of truth
SESSIONS: dict[str, Session] = {}


class Inp(BaseModel):
    kind: str      # "keypad" | "speech"
    value: str = ""
    nonce: str | None = None       # T14: replay protection

class TTSRequest(BaseModel):
    text: str


class Limit(BaseModel):
    limit: int


@app.get("/")
def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))


@app.post("/session/start")
def start(request: Request):
    sid = uuid.uuid4().hex
    session = Session()
    SESSIONS[sid] = session
    # T10: Persist to durable store
    get_session_store().save(sid, session)
    token = security.create_session_token(sid)
    client_ip = request.client.host if request.client else "unknown"
    security.audit("SESSION_START", session_id=sid, client_ip=client_ip)
    return {"session_id": sid, "token": token, **session.start()}


@app.post("/session/{sid}/input")
def step(
    sid: str,
    inp: Inp,
    request: Request,
    x_session_token: str | None = Header(None),
    x_nonce: str | None = Header(None),
    x_idempotency_key: str | None = Header(None),
):
    # T10: Try memory cache first, then durable store
    s = SESSIONS.get(sid)
    if not s:
        s = get_session_store().load(sid)
        if s:
            SESSIONS[sid] = s  # re-cache
    if not s:
        raise HTTPException(404, "unknown session")
    if inp.kind not in ("keypad", "speech"):
        raise HTTPException(400, "kind must be keypad or speech")

    # T13: Session token verification (optional for backward compat)
    if x_session_token and not security.verify_session_token(sid, x_session_token):
        security.audit("AUTH_FAILED", session_id=sid)
        raise HTTPException(403, "invalid session token")

    # T14: Replay protection via nonce
    nonce = x_nonce or inp.nonce
    if security.check_replay(sid, nonce):
        raise HTTPException(409, "duplicate request (replay detected)")

    # T11: Idempotency key check
    if x_idempotency_key:
        cached = security.get_idempotent(x_idempotency_key)
        if cached is not None:
            return cached

    result = s.handle(inp.kind, inp.value)

    # T11: Cache result for idempotency
    if x_idempotency_key:
        security.set_idempotent(x_idempotency_key, result)

    # T10: Persist updated session state to durable store
    if not result.get("end"):
        get_session_store().save(sid, s)
    else:
        # Clean up ended sessions
        security.remove_session(sid)
        SESSIONS.pop(sid, None)
        get_session_store().delete(sid)
    return result


@app.get("/limit")
def get_limit():
    return {"limit": db.get_user(db.DEMO_USER_ID)["max_txn_limit"]}


@app.put("/limit")  # called by the website/app, never by voice
def put_limit(body: Limit):
    if not 100 <= body.limit <= 50000:
        raise HTTPException(400, "limit must be 100..50000")
    db.set_limit(db.DEMO_USER_ID, body.limit)
    return {"limit": body.limit}


@app.get("/user/info")
def user_info():
    """Return current user balance + full transaction history.
    Called by the Flutter app to sync after voice-agent transactions."""
    user = db.get_user(db.DEMO_USER_ID)
    txns = db.get_transactions(db.DEMO_USER_ID)
    return {
        "balance": user["balance"],
        "name": user["name"],
        "phone": user["phone"],
        "transactions": txns,
    }


class ContactReq(BaseModel):
    name: str
    phone_number: str

@app.get("/contacts")
def get_contacts():
    return {"contacts": db.get_contacts(db.DEMO_USER_ID)}

@app.post("/contacts")
def add_contact(req: ContactReq):
    db.add_contact(db.DEMO_USER_ID, req.name, req.phone_number)
    return {"status": "ok"}


@app.post("/stt")
async def stt_endpoint(audio: UploadFile = File(...)):
    """Transcribe an uploaded audio file using the best available STT backend.
    Used by Telegram bot or as fallback for browsers without Web Speech API."""
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(400, "empty audio file")
    text = transcribe(audio_bytes)
    return {"text": text}


@app.post("/tts")
async def tts_endpoint(req: TTSRequest):
    if not edge_tts:
        raise HTTPException(500, "edge-tts not installed")
    
    # Process text for speech (e.g., number groups, money markers, names)
    text = speakable(req.text)
    
    communicate = edge_tts.Communicate(text, voice="bn-BD-NabanitaNeural", rate="+10%")

    async def audio_stream():
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                yield chunk["data"]

    from starlette.responses import StreamingResponse
    return StreamingResponse(audio_stream(), media_type="audio/mpeg")


@app.get("/health")
def health():
    """Health check endpoint for cloud deployment platforms."""
    wa_ok = False
    try:
        wa_ok = wa_configured()
    except NameError:
        pass
    return {
        "status": "healthy",
        "service": "upay-voice-guard",
        "whatsapp_configured": wa_ok,
    }


@app.get("/audit")
def audit_log(limit: int = 50):
    """T14: Return recent security audit log entries."""
    return {"entries": security.get_audit_log(limit)}

