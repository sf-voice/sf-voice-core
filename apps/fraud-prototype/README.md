# fraud-prototype

End-to-end phone-line fraud/scam detection prototype, ported from the Elixir version in `apps/ellie_ai`. **Standalone** — does not import from or depend on Ellie, and cannot affect Ellie's runtime.

## What it does

1. A **scammer AI** persona dials your real phone via Telnyx and runs a scam script (IRS, gift-cards-grandparent, fake bank fraud, fake tech support, customs/package, romance-investment).
2. A **side-listener** (`FraudDetector`) watches the live transcript every turn and scores it via regex heuristics + an LLM classifier.
3. On threshold breach, the **responder** hangs up the scammer leg and dials your phone back with a spoken summary.
4. Saying `STOP TEST` on the line is a hard-coded operator override that aborts the call.

## Setup

```sh
pnpm install   # or npm/yarn — package.json works with all of them
cp .env.example .env
# fill in TELNYX_API_KEY, OPENAI_API_KEY, FRAUD_ALERT_PHONE_E164, PUBLIC_URL, etc.
```

Public URL: Telnyx needs to reach your webhook + media-streaming endpoints. In dev, an `ngrok http 4000` tunnel pointed at `http://localhost:4000` works — set `PUBLIC_URL=https://<your-ngrok>.ngrok.app`.

## Build / typecheck

Build uses [`tsgo`](https://github.com/microsoft/typescript-go) (the Go-based TypeScript compiler from Microsoft) via the `@typescript/native-preview` package.

```sh
pnpm run typecheck   # tsgo --noEmit
pnpm run build       # tsgo --build → dist/
```

If `tsgo` is unavailable in your toolchain, the `typescript` package is installed as a fallback — `npx tsc -p tsconfig.json` produces the same output.

## Run

```sh
pnpm run dev         # node --watch with experimental TS strip
pnpm run start       # production: node dist/server.js
```

The server exposes:

* `POST /telnyx/webhook` — Telnyx call-control webhooks.
* `GET /telnyx/media-streaming` — Telnyx media-streaming WebSocket.
* `GET /health` — health check.

## Trigger a test call

```sh
pnpm run scammer -- --script irs
pnpm run scammer -- --script gift_cards_grandparent --to +15551234567
```

Available scripts: `irs`, `gift_cards_grandparent`, `fake_bank_fraud`, `fake_tech_support`, `package_customs`, `romance_investment`.

Say `STOP TEST` on the line at any time to abort.

## Layout

```text
src/
  config.ts           env loading + validation
  log.ts              pino-style minimal logger
  store/calls.ts      in-memory per-call state (replaces Elixir ETS)
  telnyx/
    client.ts         HTTP client for call-control actions (dial, hangup, speak, streaming_start)
    webhook.ts        webhook handler
  media/
    realtime.ts       OpenAI Realtime WebSocket client
    bridge.ts         Telnyx PCMU ↔ OpenAI Realtime bridge
  scammer/
    scammer.ts        outbound dialer + leg tracking
    scripts.ts        6 persona prompts (ported from Elixir)
  fraud/
    detector.ts       per-turn analyzer
    heuristics.ts     regex + keyword rules
    llm.ts            OpenAI chat completions JSON classifier
    responder.ts      hangup + alert dial + speak summary
  server.ts           Fastify app (HTTP + WS)
  cli/scammer.ts      CLI entry to dial a test call
tests/
  heuristics.test.ts
```

## What's deliberately out of v1

* Modular backend (KugelAudio STT + ElevenLabs TTS + Anthropic Claude streaming) — Elixir version has contract-only stubs; this port skips them entirely.
* DB persistence — events go to the logger only.
* DTMF "press 1 to confirm" — hang-up-first.
* Per-org alert phone settings — single env var.
