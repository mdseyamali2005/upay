"""Security middleware for upay Voice Guard.

Provides:
  T13 — Authenticated sessions & CORS restriction
  T14 — Rate limiting, lockout, & replay protection with audit logging
  T11 — Idempotency key support for transaction endpoints
"""
import hashlib
import hmac
import logging
import os
import secrets
import time
from collections import defaultdict
from dataclasses import dataclass, field

log = logging.getLogger(__name__)

# ── Configuration ──
RATE_LIMIT_WINDOW = 60          # seconds
RATE_LIMIT_MAX_REQUESTS = 30    # max requests per window per IP
LOCKOUT_THRESHOLD = 50          # lock out after this many requests in window
LOCKOUT_DURATION = 300           # lockout for 5 minutes
ALLOWED_ORIGINS = [
    "http://localhost:*",
    "http://127.0.0.1:*",
    "http://172.20.10.*:*",       # Mobile hotspot subnet
    "http://192.168.*.*:*",       # Common LAN
    "http://10.*.*.*:*",          # Private network
]
SESSION_TOKEN_BYTES = 32
IDEMPOTENCY_TTL = 3600           # 1 hour TTL for idempotency keys


@dataclass
class RateState:
    """Per-IP request rate tracking."""
    requests: list = field(default_factory=list)  # list of timestamps
    locked_until: float = 0.0


class SecurityManager:
    """Centralized security state manager."""

    def __init__(self):
        # Rate limiting
        self._rates: dict[str, RateState] = defaultdict(RateState)
        # Session tokens: session_id → token_hash
        self._session_tokens: dict[str, str] = {}
        # Idempotency cache: key → (result, timestamp)
        self._idempotency: dict[str, tuple[dict, float]] = {}
        # Audit log (in-memory, last 1000 entries)
        self._audit: list[dict] = []
        self._max_audit = 1000
        # Replay protection: set of (session_id, nonce) pairs
        self._seen_nonces: dict[str, set] = defaultdict(set)

    # ── Rate Limiting ──

    def check_rate_limit(self, client_ip: str) -> tuple[bool, str]:
        """Returns (allowed, reason). Cleans old entries."""
        state = self._rates[client_ip]
        now = time.time()

        # Check lockout
        if now < state.locked_until:
            remaining = int(state.locked_until - now)
            return False, f"Rate limited. Try again in {remaining}s."

        # Clean old requests
        cutoff = now - RATE_LIMIT_WINDOW
        state.requests = [t for t in state.requests if t > cutoff]

        # Check if exceeds lockout threshold
        if len(state.requests) >= LOCKOUT_THRESHOLD:
            state.locked_until = now + LOCKOUT_DURATION
            self.audit("LOCKOUT", client_ip=client_ip,
                       detail=f"Locked for {LOCKOUT_DURATION}s after {len(state.requests)} requests")
            return False, f"Too many requests. Locked for {LOCKOUT_DURATION}s."

        # Check rate limit
        if len(state.requests) >= RATE_LIMIT_MAX_REQUESTS:
            return False, "Rate limit exceeded. Slow down."

        state.requests.append(now)
        return True, "ok"

    # ── Session Token Management ──

    def create_session_token(self, session_id: str) -> str:
        """Generate a session authentication token."""
        token = secrets.token_hex(SESSION_TOKEN_BYTES)
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        self._session_tokens[session_id] = token_hash
        return token

    def verify_session_token(self, session_id: str, token: str) -> bool:
        """Verify a session token."""
        expected_hash = self._session_tokens.get(session_id)
        if not expected_hash:
            return False
        provided_hash = hashlib.sha256(token.encode()).hexdigest()
        return hmac.compare_digest(provided_hash, expected_hash)

    def remove_session(self, session_id: str):
        """Clean up session security state."""
        self._session_tokens.pop(session_id, None)
        self._seen_nonces.pop(session_id, None)

    # ── Replay Protection ──

    def check_replay(self, session_id: str, nonce: str | None) -> bool:
        """Returns True if this is a replay (duplicate nonce)."""
        if nonce is None:
            return False  # No nonce provided = no replay protection
        if nonce in self._seen_nonces[session_id]:
            self.audit("REPLAY_BLOCKED", session_id=session_id,
                       detail=f"Duplicate nonce: {nonce}")
            return True
        self._seen_nonces[session_id].add(nonce)
        return False

    # ── Idempotency Keys ──

    def get_idempotent(self, key: str) -> dict | None:
        """Check if an idempotency key has a cached result."""
        entry = self._idempotency.get(key)
        if entry is None:
            return None
        result, ts = entry
        if time.time() - ts > IDEMPOTENCY_TTL:
            del self._idempotency[key]
            return None
        return result

    def set_idempotent(self, key: str, result: dict):
        """Cache a result for an idempotency key."""
        self._idempotency[key] = (result, time.time())
        # Cleanup old entries
        self._cleanup_idempotency()

    def _cleanup_idempotency(self):
        now = time.time()
        expired = [k for k, (_, ts) in self._idempotency.items()
                   if now - ts > IDEMPOTENCY_TTL]
        for k in expired:
            del self._idempotency[k]

    # ── Audit Logging ──

    def audit(self, event: str, **kwargs):
        """Log a security event."""
        entry = {
            "ts": time.time(),
            "event": event,
            **kwargs,
        }
        self._audit.append(entry)
        if len(self._audit) > self._max_audit:
            self._audit = self._audit[-self._max_audit:]
        log.info("AUDIT: %s %s", event, kwargs)

    def get_audit_log(self, limit: int = 50) -> list[dict]:
        """Return recent audit entries."""
        return self._audit[-limit:]


# Singleton instance
security = SecurityManager()
