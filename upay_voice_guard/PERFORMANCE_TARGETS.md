# T12: Latency, Throughput & Recovery Targets

## Performance Targets

### Latency Targets (P95 — 95th Percentile)

| Operation | Target | Current (measured) | Notes |
|-----------|--------|-------------------|-------|
| **PIN verification** | ≤ 50ms | ~5ms | SQLite local read + PBKDF2 hash |
| **NLU (rule-based only)** | ≤ 10ms | ~1ms | Pure Python regex/keyword |
| **NLU (Gemini fallback)** | ≤ 2,000ms | ~800ms | Network round-trip to Gemini API |
| **NLU (combined pipeline)** | ≤ 2,000ms | ~1–800ms | Rule-based resolves 82.4% instantly |
| **Risk scoring** | ≤ 100ms | ~10ms | SQLite queries (5 signals) |
| **Cash-out transaction** | ≤ 200ms | ~15ms | Atomic SQLite UPDATE + INSERT |
| **TTS (edge-tts)** | ≤ 3,000ms | ~1,500ms | Streaming; first audio chunk ~500ms |
| **STT (client-side)** | ≤ 5,000ms | ~2,000ms | Web Speech API on device |
| **Full conversation step** | ≤ 4,000ms | ~2,000ms | End-to-end (input → response) |
| **Session start** | ≤ 100ms | ~5ms | UUID generation + token creation |
| **Health check** | ≤ 50ms | ~2ms | No DB access |

### Throughput Targets

| Metric | Target | Current Capacity | Bottleneck |
|--------|--------|------------------|------------|
| **Concurrent sessions** | 100 | ~50 (in-memory limit) | Python GIL + SQLite |
| **Requests/second** | 50 rps | ~30 rps (rate limit) | Rate limiter set to 30/min per IP |
| **TTS audio generation** | 20 concurrent | ~10 | edge-tts HTTP connections |
| **Gemini API calls** | 60/min | 15/min (free tier) | API quota |
| **SQLite write throughput** | 100 writes/sec | ~500 writes/sec | WAL mode not yet enabled |

### Resource Budgets

| Resource | Budget | Justification |
|----------|--------|---------------|
| **Memory per session** | ≤ 5 KB | Session state + context dict |
| **Memory (100 sessions)** | ≤ 500 KB | 100 × 5 KB |
| **Server total memory** | ≤ 256 MB | FastAPI + uvicorn + sessions |
| **Database file size** | ≤ 100 MB | SQLite file for 100K transactions |
| **Audit log retention** | 1,000 entries (in-memory) | Last ~24h at moderate traffic |

## Recovery Targets

### Failure Modes & Recovery

| Failure | Detection | Recovery | RTO | Data Loss |
|---------|-----------|----------|-----|-----------|
| **Server crash** | Process exit | Uvicorn auto-restart (systemd) | ≤ 5s | In-memory sessions lost; DB intact |
| **SQLite corruption** | Write error | WAL checkpoint + DB copy backup | ≤ 60s | Last uncommitted txn |
| **Gemini API down** | HTTP timeout (5s) | Fallback to rule-based NLU | 0s (automatic) | None — graceful degradation |
| **edge-tts down** | HTTP timeout (10s) | Return error; client shows text | ≤ 1s | None — text fallback |
| **Rate limit lockout** | 429 response | Auto-unlock after 300s | 300s | None |
| **PIN lockout** | 3 failures | Manual unlock via 16268 | Manual | None |
| **Network disconnect** | Client timeout | Client retry / new session | ≤ 10s | Current session state lost |
| **Concurrent writes** | SQLite lock | Retry with backoff (3 attempts) | ≤ 500ms | None |

### Recovery Definitions

| Term | Target |
|------|--------|
| **RTO** (Recovery Time Objective) | ≤ 30 seconds for server restart |
| **RPO** (Recovery Point Objective) | 0 (no committed transaction loss) |
| **MTBF** (Mean Time Between Failures) | ≥ 720 hours (30 days) |
| **MTTR** (Mean Time To Recovery) | ≤ 5 minutes (automated restart) |

## Scaling Path

### Horizontal Scaling (Production)

```
Current (Single Instance):
  1 uvicorn worker → 1 SQLite → 50 sessions

Target (Multi-Instance):
  N uvicorn workers → Redis (sessions) + PostgreSQL (data)
  
  Load Balancer (nginx/HAProxy)
       │
  ┌────┼────┐
  │    │    │
  W1   W2   W3  (uvicorn workers)
  │    │    │
  └────┼────┘
       │
  ┌────┼────┐
  │         │
  Redis   PostgreSQL
  (sessions)  (data)
```

### Capacity Planning

| Users | Sessions/hr | Gemini calls/hr | TTS hours/hr | Infra needed |
|-------|-------------|-----------------|--------------|--------------|
| 100 | 50 | 150 | 2.5 | 1 server |
| 1,000 | 500 | 1,500 | 25 | 2 servers + Redis |
| 10,000 | 5,000 | 15,000 | 250 | 5 servers + managed DB |
| 100,000 | 50,000 | 150,000 | 2,500 | Auto-scale cluster |

## Monitoring & Alerts

### Key Metrics to Monitor

| Metric | Alert Threshold | Action |
|--------|----------------|--------|
| Response time P95 | > 5,000ms | Scale up workers |
| Error rate (5xx) | > 5% | Investigate logs |
| Active sessions | > 80% capacity | Preemptive scale |
| Gemini API errors | > 10% | Switch to rule-only mode |
| SQLite lock waits | > 100ms | Migrate to PostgreSQL |
| Memory usage | > 80% | Restart + investigate leak |
| Disk I/O | > 80% utilization | Upgrade storage tier |
