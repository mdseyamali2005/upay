"""T10: Durable Session Storage — pluggable session backend.

Provides:
  - InMemorySessionStore (default, current behavior)
  - SQLiteSessionStore (durable, single-instance)
  - RedisSessionStore (durable, multi-instance production)

The session store is selected via the VG_SESSION_STORE environment variable:
  - "memory" (default) → InMemorySessionStore
  - "sqlite" → SQLiteSessionStore (uses voice_guard_sessions.db)
  - "redis"  → RedisSessionStore (requires REDIS_URL env var)

Usage:
  from app.session_store import get_session_store
  store = get_session_store()
  store.save("sid", session)
  session = store.load("sid")
  store.delete("sid")
"""
import json
import logging
import os
import pickle
import sqlite3
import time
from abc import ABC, abstractmethod
from contextlib import contextmanager
from typing import Optional

log = logging.getLogger(__name__)

# Session TTL: auto-expire after 30 minutes of inactivity
SESSION_TTL = 1800  # seconds


class SessionStore(ABC):
    """Abstract base class for session storage backends."""

    @abstractmethod
    def save(self, session_id: str, session) -> None:
        """Persist a session object."""

    @abstractmethod
    def load(self, session_id: str) -> Optional[object]:
        """Load a session object, or None if expired/missing."""

    @abstractmethod
    def delete(self, session_id: str) -> None:
        """Remove a session."""

    @abstractmethod
    def exists(self, session_id: str) -> bool:
        """Check if a session exists and is not expired."""

    @abstractmethod
    def list_active(self) -> list[str]:
        """List all active (non-expired) session IDs."""

    @abstractmethod
    def cleanup_expired(self) -> int:
        """Remove expired sessions. Returns count of removed sessions."""


class InMemorySessionStore(SessionStore):
    """Original in-memory session store (default).

    Fast but loses all sessions on server restart.
    Suitable for single-instance development/demo."""

    def __init__(self):
        self._sessions: dict[str, tuple[object, float]] = {}  # sid → (session, last_access)
        log.info("Session store: InMemory (sessions lost on restart)")

    def save(self, session_id: str, session) -> None:
        self._sessions[session_id] = (session, time.time())

    def load(self, session_id: str) -> Optional[object]:
        entry = self._sessions.get(session_id)
        if entry is None:
            return None
        session, last_access = entry
        if time.time() - last_access > SESSION_TTL:
            self.delete(session_id)
            return None
        # Update last access time
        self._sessions[session_id] = (session, time.time())
        return session

    def delete(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)

    def exists(self, session_id: str) -> bool:
        entry = self._sessions.get(session_id)
        if entry is None:
            return False
        _, last_access = entry
        if time.time() - last_access > SESSION_TTL:
            self.delete(session_id)
            return False
        return True

    def list_active(self) -> list[str]:
        self.cleanup_expired()
        return list(self._sessions.keys())

    def cleanup_expired(self) -> int:
        now = time.time()
        expired = [sid for sid, (_, ts) in self._sessions.items()
                   if now - ts > SESSION_TTL]
        for sid in expired:
            del self._sessions[sid]
        return len(expired)


class SQLiteSessionStore(SessionStore):
    """SQLite-backed durable session store (T10).

    Survives server restarts. Suitable for single-instance production.
    Sessions are serialized as pickle blobs."""

    def __init__(self, db_path: str = "voice_guard_sessions.db"):
        self._db_path = db_path
        self._init_db()
        log.info("Session store: SQLite (%s)", db_path)

    @contextmanager
    def _db(self):
        c = sqlite3.connect(self._db_path)
        c.row_factory = sqlite3.Row
        try:
            yield c
            c.commit()
        finally:
            c.close()

    def _init_db(self):
        with self._db() as c:
            c.execute("""
                CREATE TABLE IF NOT EXISTS sessions (
                    session_id TEXT PRIMARY KEY,
                    data BLOB NOT NULL,
                    state TEXT NOT NULL DEFAULT '',
                    last_access REAL NOT NULL
                )
            """)

    def save(self, session_id: str, session) -> None:
        data = pickle.dumps(session)
        state = getattr(session, 'state', '')
        with self._db() as c:
            c.execute(
                "INSERT OR REPLACE INTO sessions (session_id, data, state, last_access) "
                "VALUES (?, ?, ?, ?)",
                (session_id, data, state, time.time())
            )

    def load(self, session_id: str) -> Optional[object]:
        with self._db() as c:
            row = c.execute(
                "SELECT data, last_access FROM sessions WHERE session_id=?",
                (session_id,)
            ).fetchone()
            if row is None:
                return None
            if time.time() - row["last_access"] > SESSION_TTL:
                self.delete(session_id)
                return None
            # Update last access
            c.execute(
                "UPDATE sessions SET last_access=? WHERE session_id=?",
                (time.time(), session_id)
            )
            return pickle.loads(row["data"])

    def delete(self, session_id: str) -> None:
        with self._db() as c:
            c.execute("DELETE FROM sessions WHERE session_id=?", (session_id,))

    def exists(self, session_id: str) -> bool:
        with self._db() as c:
            row = c.execute(
                "SELECT last_access FROM sessions WHERE session_id=?",
                (session_id,)
            ).fetchone()
            if row is None:
                return False
            if time.time() - row["last_access"] > SESSION_TTL:
                self.delete(session_id)
                return False
            return True

    def list_active(self) -> list[str]:
        self.cleanup_expired()
        with self._db() as c:
            rows = c.execute("SELECT session_id FROM sessions").fetchall()
            return [r["session_id"] for r in rows]

    def cleanup_expired(self) -> int:
        cutoff = time.time() - SESSION_TTL
        with self._db() as c:
            cur = c.execute("DELETE FROM sessions WHERE last_access < ?", (cutoff,))
            return cur.rowcount


class RedisSessionStore(SessionStore):
    """Redis-backed durable session store (T10 production).

    Supports multi-instance deployment. Sessions auto-expire via Redis TTL.
    Requires: pip install redis
    Config: REDIS_URL environment variable (default: redis://localhost:6379/0)
    """

    def __init__(self, redis_url: str = None):
        try:
            import redis
        except ImportError:
            raise ImportError(
                "Redis session store requires 'redis' package. "
                "Install with: pip install redis"
            )
        url = redis_url or os.environ.get("REDIS_URL", "redis://localhost:6379/0")
        self._redis = redis.from_url(url, decode_responses=False)
        self._prefix = "vg:session:"
        log.info("Session store: Redis (%s)", url.split("@")[-1])  # hide password

    def _key(self, session_id: str) -> str:
        return f"{self._prefix}{session_id}"

    def save(self, session_id: str, session) -> None:
        data = pickle.dumps(session)
        self._redis.setex(self._key(session_id), SESSION_TTL, data)

    def load(self, session_id: str) -> Optional[object]:
        data = self._redis.get(self._key(session_id))
        if data is None:
            return None
        # Refresh TTL on access
        self._redis.expire(self._key(session_id), SESSION_TTL)
        return pickle.loads(data)

    def delete(self, session_id: str) -> None:
        self._redis.delete(self._key(session_id))

    def exists(self, session_id: str) -> bool:
        return bool(self._redis.exists(self._key(session_id)))

    def list_active(self) -> list[str]:
        keys = self._redis.keys(f"{self._prefix}*")
        prefix_len = len(self._prefix)
        return [k.decode()[prefix_len:] if isinstance(k, bytes) else k[prefix_len:]
                for k in keys]

    def cleanup_expired(self) -> int:
        # Redis handles TTL-based expiry automatically
        return 0


# ── Factory ──

_store_instance: Optional[SessionStore] = None


def get_session_store() -> SessionStore:
    """Get or create the configured session store singleton."""
    global _store_instance
    if _store_instance is None:
        backend = os.environ.get("VG_SESSION_STORE", "memory").lower()
        if backend == "sqlite":
            _store_instance = SQLiteSessionStore()
        elif backend == "redis":
            _store_instance = RedisSessionStore()
        else:
            _store_instance = InMemorySessionStore()
    return _store_instance


def reset_session_store():
    """Reset the session store singleton (for testing)."""
    global _store_instance
    _store_instance = None
