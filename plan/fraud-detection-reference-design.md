# Fraud-Detection / Prevention AI — Reference Design

> What a production-grade, real-time phone-fraud-prevention AI *should* look like
> for sf-voice / ellie. This is the target, not the current state. The companion
> doc [`fraud-detection-gap-analysis.md`](./fraud-detection-gap-analysis.md) maps
> our implementation against it.

## 1. Problem framing

Goal: protect a **human operator** (the person ellie dials, or who is on a live
call) from financial and identity loss caused by **social-engineering phone
scams** — impersonation (IRS, bank, tech support, family emergency), payment
coercion (gift cards, wire, crypto), and remote-access takeover.

Three distinct jobs, often conflated:

| Job | Question | Failure if absent |
|-----|----------|-------------------|
| **Detection** | Is this call a scam, and how sure are we? | Miss the scam (FN) |
| **Decision** | Given a score + context, what do we do *now*? | Act too early/late |
| **Prevention / response** | Intervene to stop the loss | Detect but don't help |

A good system treats these as separate, independently-testable stages. Detection
that can't drive a calibrated, graduated response is a dashboard, not a
preventer.

## 2. Detection — layered signals (defense in depth)

No single signal is sufficient. Each layer has a different cost, latency, and
failure mode; the ensemble is what makes it robust.

### 2.1 Lexical / heuristic (cheap, deterministic, explainable)
- Regex / keyword rules over the rolling transcript: payment-method tells,
  authority impersonation, urgency/secrecy, remote-access tools, victim-
  compliance markers.
- Always-on, sub-millisecond, no network. The **floor** of the system —
  everything else can fail and this still trips.
- Must carry **evidence labels** (which rule fired) for explainability.

### 2.2 Semantic / LLM classifier (context-aware)
- An LLM reads the conversation and returns a calibrated score + short reason.
- Catches paraphrase and novel scripts heuristics miss.
- Needs a strict latency budget and a JSON contract; must degrade gracefully
  (fall back to heuristics) on timeout/error.

### 2.3 Acoustic / audio (the multimodal layer)
- **Synthetic-voice / deepfake detection** — is the caller AI-generated?
- **Spoofing / replay detection.**
- **Prosody & stress** — caller cadence (scripted call-center delivery),
  victim stress/confusion rising over the call.
- This is the layer most phone-fraud systems lack and where a voice-AI company
  has a structural advantage. Should be a first-class scorer, not an afterthought.

### 2.4 Metadata / reputation (pre-conversation signals)
- Caller-ID / ANI reputation, **STIR/SHAKEN attestation level**, carrier
  spam labels, number-velocity (one number dialing many targets), known-fraud
  lists. Available *before* a word is spoken — enables pre-answer screening.

### 2.5 Behavioral / conversational dynamics (temporal)
- Turn-taking patterns, pressure escalation *over time*, script-adherence,
  topic drift toward payment. Single turns look benign; the *trajectory* is the
  signal.

### 2.6 Cross-call / account (graph)
- Velocity and repeat-targeting across calls, shared-number graphs, campaign
  fingerprints. Turns per-call detection into population-level prevention.

## 3. Scoring & decision

- **Calibrated probabilities**, not raw maxima. `max(heuristic, llm)` is a
  starting heuristic but is not a probability and double-counts correlated
  signals. Target: a weighted/learned ensemble producing a calibrated `p(fraud)`
  with per-signal confidence.
- **Hysteresis / debounce** — require sustained or corroborated signal before a
  hard action; a single keyword should *raise* score, not *terminate* a call.
- **Tiered thresholds** — `monitor → warn → soft-intervene → hard-intervene`,
  each with its own threshold, rather than one fire-once boolean.
- **Time-decay & escalation** — recent turns weigh more; score escalates as
  corroborating signals stack.
- **Explainability** — every decision carries the evidence trail (which signals,
  what weights, what crossed) for audit and for the human-facing alert.
- **Hard overrides** — an operator safety phrase ("STOP TEST"-style) must
  short-circuit everything. This is correct and should stay.

## 4. Prevention / response ladder (graduated)

A single "hang up + call back" is one rung. The full ladder:

1. **Silent monitor + log** — score below warn threshold; record evidence.
2. **Real-time user warning** — whisper/beep/spoken caution to the *operator*
   mid-call ("this may be a scam — do not share payment info").
3. **Soft intervention** — inject verification prompts, slow the call, ask the
   caller to confirm identity.
4. **Hard intervention** — terminate the fraudulent leg; block the number.
5. **Post-call** — alert the user via callback / SMS / push with a summary;
   report number to carrier / blocklist; optionally to authorities.
6. **Human-in-the-loop** — ambiguous high-stakes cases route to a human
   reviewer before a hard action.

Each rung is independently configurable and testable. The response orchestrator
should be idempotent and durable (a crash mid-response must not double-dial or
drop the alert).

## 5. Feedback & continuous learning

- **Outcome labels** — capture confirmed-fraud / confirmed-benign / unknown for
  every triggered call; feed threshold tuning and model training.
- **FP / FN review queue** — false positives (hanging up a legit call) are
  high-cost; they need an explicit review path.
- **Red-team eval harness** — adversarial scammer personas that dial the system
  and measure detection rate, time-to-detect, and intervention success. (We
  already have the bones of this — see gap analysis.)
- **Offline eval datasets** — labeled transcripts + audio for regression
  testing every change to rules/prompts/thresholds.
- **Drift monitoring** — scam scripts evolve; track precision/recall over time
  and alert on degradation.
- **Metrics that matter**: precision, recall, **time-to-detect**, intervention
  success rate, FP rate per 1k calls, cost per call.

## 6. Safety, privacy, compliance

- **Recording / monitoring consent** — two-party-consent jurisdictions require
  disclosure. Must be enforced before any transcript is scored or stored.
- **PII handling** — transcripts contain card numbers, SSNs, names. Redaction at
  rest, retention limits, access control, audit log.
- **False-positive harm** — terminating a legitimate call (real bank, real
  family) is a real harm. Bias toward *warning* over *terminating* until
  confidence is high.
- **Fairness** — detection must not degrade across accents, languages, or
  demographics; eval across cohorts.
- **Regulatory** — TCPA (outbound dialing), GDPR/CCPA (data), STIR/SHAKEN.

## 7. Reliability & operations

- **Latency budget** — detection must act *mid-call*. Define an end-to-end
  budget (e.g. transcript-turn → decision < ~1s) and enforce per-stage timeouts.
- **Graceful degradation** — LLM/STT/audio-scorer down ⇒ heuristics still run
  and can still trigger. No single dependency is allowed to disable prevention.
- **Durability** — fired-state, alert pairings, and number reputation must
  survive a process restart. Ephemeral in-memory state means a crash mid-scam
  re-fires or loses the alert.
- **Idempotency** — dedupe triggers per call; the response ladder must not
  double-act on retries.
- **Observability** — per-signal latency, trigger counts, FP/FN, cost, queue
  depth; alerting on anomalies.
- **Concurrency & cost control** — bound concurrent LLM/audio calls; backpressure
  under load; per-tenant cost ceilings.

## 8. Reference architecture

```
                         ┌───────────────────────────────────────────────┐
  Telnyx leg  ──audio──▶ │  STT / transcript turns (rolling, per ccid)    │
  metadata    ──────────▶│                                                │
                         └───────────────┬───────────────────────────────┘
                                         │ finalized turn + audio frame
                         ┌───────────────▼───────────────────────────────┐
                         │  Signal scorers (pluggable registry)           │
                         │   • Heuristics   • LLM classifier              │
                         │   • Acoustic     • Reputation/metadata         │
                         │   • Behavioral   • Cross-call/graph            │
                         └───────────────┬───────────────────────────────┘
                                         │ [{signal, score, confidence, evidence}]
                         ┌───────────────▼───────────────────────────────┐
                         │  Aggregator → calibrated p(fraud) + evidence   │
                         │  Decision engine (tiered thresholds, hysteresis)│
                         └───────────────┬───────────────────────────────┘
                                         │ decision: monitor|warn|soft|hard
                         ┌───────────────▼───────────────────────────────┐
                         │  Response orchestrator (idempotent, durable)   │
                         │   warn ▸ soft-intervene ▸ hangup ▸ callback ▸  │
                         │   blocklist ▸ human review                     │
                         └───────────────┬───────────────────────────────┘
                                         │ events
                         ┌───────────────▼───────────────────────────────┐
                         │  Durable store + eval/feedback loop            │
                         │  (outcomes, labels, metrics, red-team harness) │
                         └────────────────────────────────────────────────┘
```

Key properties: scorers are a **registry** (add a signal without touching the
detector), decision is **separate** from detection, response is **graduated**,
state is **durable**, and the whole thing is wrapped by an **eval/feedback loop**
fed by the red-team scammer harness.
