# Open questions for v2

- **Customer S3 auth.** IAM role assumption (recommended) vs stored access keys. Schema reserves the columns. Onboarding flow TBD.
- **Embedding store at scale.** DuckDB on a single node is fine through v1 (millions of rows, sub-second k-NN). When we cross node boundaries the options are ClickHouse vector indexes, pgvector, or a dedicated store. Driven by call volume.
- **Multi-model embeddings.** `transcript_embeddings.model` is part of the PK so multiple embedding versions can coexist for the same utterance. v1 stores only one model; v2 might A/B `text-embedding-3-small` vs `text-embedding-3-large` per org.
- **Speaker-identity mapping.** When tracks are mixed (no separated `caller_audio_uri` / `ai_audio_uri`), how do we label utterances? Loudest channel? Known TTS voiceprint? Telnyx side-tag? v1 falls back to `unknown`.
- **Real sandbox.** Spin up an actual instance of the customer's voice agent against a config branch and regenerate the slice's AI response.
- **Real PR creation.** GitHub App on the per-customer config repo; commit + open PR programmatically.
- **Live-watch.** Stream a call as it happens. Adds websockets and a hot-path event pipe.
- **Anomaly auto-detection.** Surface calls with slow turns / interrupts / dead air without the user filtering for them.
- **Cross-call dashboards.** p50 latency over time, week-over-week trends.
