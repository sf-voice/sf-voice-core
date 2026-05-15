# Search use-cases mapped to schema

- **"When did AI interrupt caller"** — self-join `transcripts` (MySQL) on `call_id` where `speaker_label='ai'` overlaps a `speaker_label='caller'` row by `start_ms`/`end_ms`. Covered by `idx_transcripts_call_start`.

  ```sql
  SELECT a.call_id, a.start_ms
  FROM transcripts a
  JOIN transcripts b ON a.call_id = b.call_id
  WHERE a.speaker_label = 'ai'
    AND b.speaker_label = 'caller'
    AND a.start_ms BETWEEN b.start_ms AND b.end_ms;
  ```

- **"Why are customers dropping calls"** — semantic search over `transcript_embeddings` in DuckDB, filtered by `org_id`, often combined with `calls.termination_reason`. The query "customers giving up" embeds + finds the closest utterances; the joined `calls.termination_reason` separates real drops from completions. See [`duckdb-vectors.md`](duckdb-vectors.md) for the SQL pattern.

- **Topic clustering** — `transcript_embeddings.embedding` is the input. v1 surface: ad-hoc DuckDB queries from notebooks. v2: a clustering job that writes a `cluster_id` back per transcript for filter UIs.

- **Keyword search across transcripts** — MySQL `MATCH(text) AGAINST(...)` on `transcripts.text` (FULLTEXT index). Cheaper than embeddings when the user types literal phrases.

- **"Calls that hit a latency threshold"** — phase 2. Needs `call_events` (ClickHouse) joined to `calls.org_id` (MySQL).
