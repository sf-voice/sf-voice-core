# Pipeline contracts

- **End-of-turn VAD service.** Phoenix Channel on ellie (NOT HTTP). URL via env (`VAD_WS_URL`, e.g. `ws://ellie-ai:4001/socket/vad` in prod, `ws://127.0.0.1:4001/socket/vad` in dev). Auth: bearer `INTERNAL_API_TOKEN` passed on connect; ellie's `VadSocket.connect/3` calls `Plug.Crypto.secure_compare/2`. Frames are pushed as Phoenix v2 binary; the server replies with `{:turn, :speech_start | :speech_end}` events plus VAD probabilities. **Contract source of truth:** `apps/ellie_ai/lib/ellie_ai_web/channels/vad_channel.ex` (server) and `core/backend/api/src/vad.rs` (client). Smoke test: `infra/deploy/smoke-vad.py`.
- **Whisper.** OpenAI hosted, `whisper-large-v3` via `/v1/audio/transcriptions`. API key from `OPENAI_API_KEY`.
- **Diarization.** `pyannote-3.1` proposed (huggingface inference endpoint). URL via env (`DIARIZE_URL`). Confirm model and host before wiring.
- **Embeddings.** OpenAI `text-embedding-3-small` via `/v1/embeddings`. 1536 dims. Same `OPENAI_API_KEY`. Called once per utterance during the `transcribe` job (batched in groups of up to 100 per request).
- **Slack webhook.** URL per org from `orgs.slack_webhook_url`. Posted on every `jobs.progress_steps` append. First post stores `slack_thread_ts`; subsequent posts thread into it.
