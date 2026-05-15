# Analytics events (ClickHouse Cloud)

Out of scope for v1 schema work. The design assumes a future MergeTree table for high-cardinality per-event telemetry:

```
call_events (
  org_id          UUID,
  call_id         UUID,
  ts              DateTime64(6),
  event_type      LowCardinality(String),  -- 'vad_sample','llm_token','tts_chunk','tool_call','error'
  span_id         UUID,
  parent_span_id  UUID,
  duration_ms     Float64,
  payload         String                   -- JSON
)
ORDER BY (org_id, call_id, ts);
```

The timeline's VAD curve, LLM TTFT spans, and tool-call bars will read from there in phase 2. v1 timeline uses placeholder data synthesized from `transcripts` where possible.
