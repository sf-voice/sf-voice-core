# Service overview

Rust + Axum API powering the sf-voice debugging product.

- **State store:** MySQL 8.4 (per repo-root `AGENTS.md` tech stack). Local dev via `infra/dev/docker-compose.yml`; prod via `infra/deploy/docker-compose.mysql.yml`.
- **Embedded analytical + vector store:** DuckDB. Holds per-utterance embeddings and any per-call analytical rollups. In-process inside the API binary; file at `DUCKDB_PATH` (defaults to `./data/sf_voice.duckdb`). Uses the `vss` extension for HNSW vector indexes.
- **High-volume telemetry (future):** ClickHouse Cloud. Out of scope for v1.
- **Object storage:** S3. v1 reads only from internal/test buckets owned by sf-voice. Customer-bucket auth is deferred.
- **Voice models:** OpenAI Whisper (hosted) for ASR. Diarization model TBD. End-of-turn VAD via Phoenix Channel on ellie (see [`pipeline-contracts.md`](pipeline-contracts.md)).
- **Embedding model:** OpenAI `text-embedding-3-small` (1536 dims). Same API key as Whisper.
