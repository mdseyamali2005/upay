# T5/T6/T7/T8: Business & Customer Impact Documentation

## T8: Target Persona Definition

### Primary Persona: Urban Low-Literacy MFS Customer

| Attribute | Detail |
|-----------|--------|
| **Name** | ফারুক মিয়া (Faruk Mia) |
| **Age** | 45–65 years |
| **Location** | Semi-urban / urban Bangladesh |
| **Education** | Primary school or below |
| **Digital Literacy** | Low — can make calls, limited app navigation |
| **MFS Usage** | Cash-out 2–4 times/month via agent |
| **Pain Points** | Cannot read app menus easily; fears making mistakes; relies on agent/family to navigate app; frequently enters wrong numbers |
| **Language** | Bangla (may use regional dialect: Sylheti, Chittagong, etc.) |
| **Device** | Budget Android phone (Android 9–12), small screen |

### Secondary Persona: Rural Merchant (Agent)

| Attribute | Detail |
|-----------|--------|
| **Name** | রহিমা বেগম (Rahima Begum) |
| **Age** | 30–50 years |
| **Role** | Small shop owner, upay agent |
| **Digital Literacy** | Medium — uses apps but slow |
| **Pain Points** | Processes 20–50 cash-outs/day; manual USSD codes are slow; wants voice-driven shortcuts for repeat transactions |
| **Goal** | Faster transaction processing; reduce errors during busy hours |

### Tertiary Persona: Call Center Ops

| Attribute | Detail |
|-----------|--------|
| **Role** | upay customer support (16268 helpline) |
| **Pain Point** | High call volume for simple queries (balance, charges, PIN reset) |
| **Goal** | Deflect simple queries to voice assistant; reduce average handling time |

---

## T5: Impact Metrics Definition

### Quantitative Metrics

| Metric | Definition | Measurement Method | Target |
|--------|------------|-------------------|--------|
| **Task Completion Rate** | % of voice sessions that reach a successful transaction | `count(cash_out SUCCESS) / count(session_start)` from audit log | ≥ 80% |
| **Task Completion Time** | Seconds from session start to final confirmation | Timestamps in session flow | ≤ 90 seconds (vs ~120s for app navigation) |
| **Input Error Rate** | % of sessions with ≥1 wrong number/amount entry | Track `num_tries`, `amt_tries` in flow | ≤ 15% (vs ~25% for USSD) |
| **Abandonment Rate** | % of sessions started but not completed (no transaction) | `session_start - session_complete` | ≤ 20% |
| **Intent Recognition Accuracy** | % of intents correctly classified | NLU evaluation harness (85-sample dataset) | ≥ 95% (current: 98.8%) |
| **Risk Detection Precision** | % of risk warnings that were actually risky | User feedback on risk prompts | ≥ 70% |
| **Risk Detection Recall** | % of risky transactions that triggered a warning | Labeled transaction audit | ≥ 90% |
| **False Positive Rate (Fraud)** | % of legitimate transactions flagged as risky | Track risk score vs user response | ≤ 15% |
| **User Confidence Score** | Post-task survey: "How confident were you?" (1–5) | Post-session survey prompt | ≥ 4.0 |
| **FAQ Deflection Rate** | % of FAQ queries answered without human handoff | Track FAQ vs "call 16268" responses | ≥ 60% |

### Qualitative Metrics

| Metric | Method |
|--------|--------|
| **Ease of Use** | Post-pilot interview: "Was the voice assistant easier than the app?" |
| **Trust & Safety** | "Did you feel your money was safe during the transaction?" |
| **Language Comfort** | "Could the assistant understand your dialect/accent?" |
| **Accessibility** | "Could you complete the task without reading the screen?" |

### Data Collection Infrastructure

All metrics are derivable from existing audit logs, session state, and the evaluation harness:
- **Completion rate/time**: `/session/start` → `/session/{sid}/input` timestamps in `security.audit()`
- **Error rates**: `num_tries`/`amt_tries` counters in `flow.py` session context
- **Intent accuracy**: `tests/eval_nlu.py` evaluation harness with 85-sample dataset
- **Risk metrics**: `risk.score`, `risk.factors`, user response in flow context

---

## T6: User Pilot / Validation Test Protocol

### Pilot Design

| Parameter | Value |
|-----------|-------|
| **Sample Size** | 15–20 users |
| **Demographics** | 5 older adults (55+), 5 low-literacy, 5 regular app users (control) |
| **Duration** | 1 week per cohort |
| **Environment** | Supervised in-person sessions (first 3), then unsupervised home use |
| **Tasks** | Balance check, Cash-out (known agent), Cash-out (new number), Spending query, FAQ |

### Test Protocol

1. **Baseline** (Day 1):
   - Each user performs 3 tasks using the standard upay app (timed, errors recorded)
   - Post-task survey: ease (1–5), confidence (1–5), errors encountered

2. **Voice Guard** (Day 2–7):
   - Same 3 tasks using Voice Guard
   - System logs capture: completion time, error count, abandonment, risk triggers
   - Post-task survey: same questions + "Did you prefer voice?"

3. **Comparison Analysis**:
   - Paired t-test: completion time (app vs voice)
   - McNemar test: error rate (app vs voice)
   - Wilcoxon signed-rank: confidence scores

### Expected Findings

| Metric | App (expected) | Voice Guard (expected) | Improvement |
|--------|---------------|----------------------|-------------|
| Completion Time | ~120s | ~90s | 25% faster |
| Error Rate | ~25% | ~12% | 52% fewer errors |
| Confidence (1–5) | 2.5 | 4.0 | +60% |
| Abandonment | ~30% | ~15% | 50% reduction |

### Risk Mitigation

- All transactions use demo data (synthetic accounts, fake balances)
- Informed consent obtained; users can withdraw at any time
- Facilitator present during supervised sessions
- All voice recordings are processed locally, not stored

---

## T7: Cost Estimation

### Per-Transaction Cost Analysis

| Component | Service | Cost per Transaction | Monthly (1000 txns) |
|-----------|---------|---------------------|---------------------|
| **TTS** | edge-tts (Microsoft) | Free (open API) | ৳0 |
| **TTS** (production) | Azure Speech Services | $0.016 per 1M chars ≈ ৳0.02/txn | ৳20 |
| **STT** | Web Speech API (client) | Free (browser-based) | ৳0 |
| **STT** (production) | Google Speech-to-Text | $0.006/15s ≈ ৳0.75/txn | ৳750 |
| **NLU** | Gemini 2.0 Flash | ~$0.001/request ≈ ৳0.12/txn | ৳120 |
| **Server** | VPS (2 vCPU, 4GB) | — | ৳2,000 |
| **Total (demo)** | — | ~৳0.12/txn | ৳120 + server |
| **Total (production)** | — | ~৳0.89/txn | ৳2,890 |

### Comparison vs Alternatives

| Channel | Cost per Interaction | Notes |
|---------|---------------------|-------|
| **Voice Guard** | ৳0.12–0.89 | Automated, 24/7 |
| **Call Center (16268)** | ৳15–25 | Human agent, limited hours |
| **USSD (*247#)** | ৳0.50–1.00 | Telecom charges, no voice |
| **In-app support** | ৳0 | Requires literacy, internet |
| **Agent visit** | ৳5–10 (travel) | Physical, time-consuming |

### ROI Projection

Assuming 10,000 monthly interactions deflected from call center:
- **Current cost**: 10,000 × ৳20 = ৳200,000/month
- **Voice Guard cost**: 10,000 × ৳0.89 = ৳8,900/month + ৳2,000 server = ৳10,900
- **Monthly savings**: ৳189,100 (94.5% reduction)
- **Annual savings**: ৳2,269,200 (~$19,000 USD)

### Limitations

- edge-tts is free but has no SLA; production should use Azure Speech Services
- Gemini API costs may increase with scale; consider on-premise NLU model for high volume
- STT accuracy varies by dialect; may need custom fine-tuning ($500–2,000 one-time)
