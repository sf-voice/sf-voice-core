# Fraud Detection — Implementation vs Reference Design

> Maps our current `apps/ellie_ai` fraud implementation against
> [`fraud-detection-reference-design.md`](./fraud-detection-reference-design.md).
> Current code reviewed at branch `claude/fraud-detection-prevention-swgys3`
> (the re-integrated Elixir prototype).

## What we have today (grounded in the code)

| Component | File | Role |
|-----------|------|------|
| `FraudDetector` | `lib/ellie_ai/calls/fraud_detector.ex` | Per-turn side-listener; heuristic + LLM; aggregate; dedupe; trigger |
| `FraudDetector.Heuristics` | `.../fraud_detector/heuristics.ex` | 21 regex rules, `max(weight)` scoring + evidence labels |
| `FraudResponder` | `lib/ellie_ai/calls/fraud_responder.ex` | Hang up scammer leg → dial operator → speak summary |
| `Scammer` + `Scripts` | `lib/ellie_ai/scammer*.ex` | Red-team harness: 6 outbound AI personas (OpenAI Realtime) |
| `AudioBackend` (+ Realtime/Modular) | `lib/ellie_ai/calls/audio_backend*.ex` | Backend behaviour; Realtime works, Modular is a stub |
| `Llm.Adapter` (+ Anthropic) | `lib/ellie_ai/llm/*.ex` | Streaming-LLM behaviour for modular backend; Anthropic is a stub |
| `Speech.*` (KugelAudio STT, ElevenLabs TTS) | `lib/ellie_ai/speech/*.ex` | Stubs pending APIs |
| Wiring | `telnyx_webhook_controller.ex`, `audio_bridge.ex` | Routes alert/scammer legs; installs detector hook at turn-finalize |

**How it runs today:** on each finalized transcript turn, `AudioBridge` calls
`FraudDetector.analyze_async/1` (`audio_bridge.ex:656`). The detector runs **only
for scammer legs** (gated on `Memory.scammer_script(ccid)`), scores the rolling
transcript with `max(heuristic, llm@gpt-4o-mini)`, and on crossing
`FRAUD_THRESHOLD` (default `0.7`) fires `FraudResponder` once per call (ETS
dedupe). `STOP TEST` is a hard 1.0 override. Everything is logged via
`Calls.record_system_event` (no DB migration).

## Gap table

Legend: ✅ present · 🟡 partial · ❌ missing

| # | Reference dimension | Status | Current state | Gap |
|---|---------------------|--------|---------------|-----|
| 1 | Lexical/heuristic signal | ✅ | 21 weighted regex rules + evidence labels | Solid floor. Rules are hand-tuned, English-only, no test coverage |
| 2 | Semantic/LLM signal | ✅ | `gpt-4o-mini`, JSON `{score,reason}`, 5s timeout, degrades to heuristics | Works. Not calibrated; single provider; English-only |
| 3 | Acoustic/audio signal | ❌ | None. Detector reads transcript text only | **Biggest gap.** No deepfake/spoof/prosody scoring — the layer where a voice-AI company should lead. `aggregate/1` is built to accept it, but no scorer exists |
| 4 | Metadata/reputation | ❌ | None. No ANI reputation, STIR/SHAKEN, velocity, blocklist | No pre-answer screening; reacts only after conversation starts |
| 5 | Behavioral/temporal | 🟡 | LLM sees rolling transcript, so *some* trajectory | No explicit escalation/pressure modeling; heuristics are stateless per-turn |
| 6 | Cross-call/graph | ❌ | ETS is per-process, per-call only | No population-level signal or repeat-target detection |
| 7 | Calibrated scoring | 🟡 | `max(heuristic, llm)` | Not a probability; double-counts correlated signals; no per-signal confidence |
| 8 | Hysteresis/debounce | ❌ | Single crossing of one threshold fires hard action | One strong keyword (weight 0.7) + nothing else can't fire alone (<0.7), but two can. No sustained-signal requirement |
| 9 | Tiered thresholds | ❌ | One boolean threshold, fire-once | No `monitor/warn/soft/hard` ladder |
| 10 | Graduated response | 🟡 | Hard action only: hangup + callback + speak | No silent-monitor, no mid-call user warning, no soft intervention, no human-in-loop |
| 11 | Post-call / blocklist | 🟡 | Callback with spoken summary | No SMS/push, no number blocklist, no carrier/authority reporting |
| 12 | Explainability | ✅ | Evidence labels + LLM reason in summary + system_events | Good. This is a strength |
| 13 | Hard override (safety) | ✅ | `STOP TEST` → immediate trigger | Correct as designed |
| 14 | Idempotency / dedupe | ✅ | ETS fired-set, once per ccid | Works, but state is ephemeral (see #17) |
| 15 | Graceful degradation | ✅ | LLM error/timeout ⇒ heuristics still score | Good design |
| 16 | Latency budget | 🟡 | Fire-and-forget async, 5s LLM timeout | No explicit end-to-end budget or per-stage SLO/metrics |
| 17 | Durability | ❌ | All state in ETS (`fired`, `alert_legs`, `scammer_legs`) | Process restart loses fired-set (re-fire risk) and alert pairings (dropped alert). Reference wants durable store |
| 18 | Observability/metrics | 🟡 | `system_events` rows + logs | No metrics (precision/recall/time-to-detect/FP rate/cost), no alerting |
| 19 | Feedback / learning loop | ❌ | None | No outcome labels, no FP/FN review, no threshold tuning loop |
| 20 | Red-team eval harness | 🟡 | `Scammer` + 6 personas exist | It's a manual dialer, not an automated scored eval suite with pass/fail metrics |
| 21 | Privacy / consent / PII | ❌ | Transcripts (incl. card/SSN) scored & stored as-is | No redaction, retention policy, or consent gate |
| 22 | Fairness / i18n | ❌ | English regex + English LLM prompt | No multi-language / accent coverage or cohort eval |
| 23 | Production scope | 🟡 | v1 scores **scammer legs only**; real inbound calls are skipped | By design for v1 — but it means this prevents fraud only in *tests*, not yet on real ellie calls |
| 24 | Test coverage | ❌ | No `fraud_detector`/`heuristics`/`responder` tests | `Sentiment` (the sibling it's modeled on) has tests; fraud code has none |

## Honest summary

The implementation is a **well-built v1 of one vertical slice**: text-based
heuristic+LLM detection with a clean hard-response and a red-team harness. It is
faithful to the "defense in depth → aggregate → respond" shape and has genuine
strengths (explainability, graceful degradation, the pluggable `aggregate/1`
seam, the STOP-TEST override).

Measured against the reference, the **three structural gaps** are:

1. **No audio/multimodal signal (#3)** — the detector is text-only. For a
   voice-AI company this is both the largest gap and the biggest differentiation
   opportunity. The aggregator was deliberately built to accept it.
2. **No durable state or production wiring (#17, #23)** — ETS-only state and
   scammer-leg-only scoring mean it protects test calls, not real callers, and
   loses state on restart.
3. **No feedback/eval/calibration loop (#7, #19, #20, #24)** — scoring isn't
   calibrated, there are no outcome labels, no automated eval, and no tests.

## Suggested roadmap (priority order)

**P0 — make it real & safe**
- Add tests: `heuristics_test.exs` (rule coverage + STOP-TEST), `fraud_detector`
  aggregation/threshold, `fraud_responder` happy/failure paths.
- Move ETS state (`fired`, `alert_legs`) to a durable/owned store, or at least a
  supervised ETS owner, so a restart can't re-fire or drop an alert.
- Consent + PII redaction gate before transcripts are scored/stored.

**P1 — close the response gap**
- Tiered thresholds (`monitor/warn/soft/hard`) + hysteresis instead of one
  fire-once boolean.
- Mid-call user warning rung before the hard hangup.

**P2 — the differentiator**
- Acoustic scorer (deepfake/spoof/prosody) as a new `aggregate/1` signal.
- Reputation/metadata pre-answer screening (ANI, STIR/SHAKEN, velocity).

**P3 — learn**
- Automate the `Scammer` harness into a scored eval suite (detection rate,
  time-to-detect, FP rate).
- Outcome labeling + threshold calibration; replace `max` with a calibrated
  ensemble.

## Verification note

This analysis is from static reading + dependency cross-checking against
`origin/main` (all external symbols the fraud code calls were confirmed
present). The code has **not been compiled** — there is no Elixir/mix toolchain
in the current container. Run `mix compile` + `mix test` in `apps/ellie_ai`
before relying on it.
