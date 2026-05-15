# Vector embeddings (DuckDB)

Per-utterance embeddings live in DuckDB. The Rust API opens `DUCKDB_PATH` on startup and ensures the schema below exists. Two reasons we use DuckDB and not MySQL or a separate service:

1. It's already in the binary — no new service to deploy.
2. The `vss` extension gives us HNSW indexes with sub-millisecond k-NN at our scale.

```sql
-- run on startup, idempotent
INSTALL vss;
LOAD vss;

CREATE TABLE IF NOT EXISTS transcript_embeddings (
  transcript_id  BIGINT      NOT NULL,         -- fk-by-convention to mysql transcripts.id
  call_id        UUID        NOT NULL,
  org_id         UUID        NOT NULL,
  run_id         UUID        NOT NULL,         -- which transcript_runs.id produced the row
  model          VARCHAR     NOT NULL,         -- e.g. 'openai/text-embedding-3-small'
  embedding      FLOAT[1536] NOT NULL,
  text           VARCHAR     NOT NULL,         -- denormalized for fast preview; mysql remains source of truth
  created_at     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (transcript_id, model)
);

-- hnsw index for cosine k-NN. m and ef_construction are duckdb-vss defaults.
CREATE INDEX IF NOT EXISTS idx_transcript_embeddings_hnsw
  ON transcript_embeddings
  USING HNSW (embedding)
  WITH (metric = 'cosine');

CREATE INDEX IF NOT EXISTS idx_transcript_embeddings_org
  ON transcript_embeddings (org_id);
```

**Why `transcript_id` is fk-by-convention.** DuckDB and MySQL don't share an FK enforcement boundary. The `transcribe` job is responsible for keeping these in sync: when it inserts a `transcripts` row it also inserts the matching `transcript_embeddings` row. When `transcript_runs.id` is replaced (re-transcribe), the job deletes old embedding rows for that `run_id` and writes new ones.

**Search.** `GET /api/search?q=...&limit=20` embeds `q` via the same OpenAI model, queries DuckDB:

```sql
SELECT transcript_id, call_id, text, array_cosine_distance(embedding, $1) AS dist
FROM transcript_embeddings
WHERE org_id = $2
ORDER BY dist
LIMIT $3;
```

then joins back to MySQL `transcripts` + `calls` to surface full context. The hnsw index makes this fast.
