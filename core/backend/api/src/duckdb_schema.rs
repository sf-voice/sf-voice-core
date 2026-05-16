//! duckdb schema bootstrap. runs once at startup. creates the
//! transcript_embeddings table per BRAND/AGENT.md § 5.
//!
//! we DON'T install the vss extension in v1 — exact cosine via
//! `array_cosine_distance` on the FLOAT[] column is fast enough through
//! thousands of utterances. when query latency starts to matter, add:
//!   INSTALL vss; LOAD vss;
//!   CREATE INDEX ... USING HNSW (embedding) WITH (metric='cosine');

use std::sync::{Arc, Mutex};

use duckdb::Connection;

use crate::error::AppError;

pub fn bootstrap(conn: &Arc<Mutex<Connection>>) -> Result<(), AppError> {
    let c = conn.lock().map_err(|_| AppError::Poisoned)?;
    c.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS transcript_embeddings (
            transcript_id BIGINT      NOT NULL,
            call_id       UUID        NOT NULL,
            org_id        UUID        NOT NULL,
            run_id        UUID        NOT NULL,
            model         VARCHAR     NOT NULL,
            embedding     FLOAT[1536] NOT NULL,
            text          VARCHAR     NOT NULL,
            created_at    TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (transcript_id, model)
        );

        CREATE INDEX IF NOT EXISTS idx_te_org      ON transcript_embeddings (org_id);
        CREATE INDEX IF NOT EXISTS idx_te_call     ON transcript_embeddings (call_id);
        CREATE INDEX IF NOT EXISTS idx_te_run      ON transcript_embeddings (run_id);
        "#,
    )?;
    tracing::info!("duckdb transcript_embeddings schema ready");
    Ok(())
}
