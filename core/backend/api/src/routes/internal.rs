//! /api/_internal — admin-gated endpoints for sf-voice staff only.
//!
//! NOT merged into routes::router(). mounted separately in main.rs so the
//! customer router can never accidentally inherit these handlers. each
//! handler extracts AdminContext, which enforces:
//!   - session cookie present (or 401)
//!   - user's email matches @sf-voice.sh (or 403)
//!
//! data model: the `documents` table replaces the old
//! internal_media_sources. each youtube ingest produces:
//!   - 1 parent doc (raw.mp4, source_url = the youtube link)
//!   - 3 derived docs (video.mp4, audio.m4a, audio.wav) pointing at
//!     the parent via source_id
//! see migrations/0006_documents.sql for the full schema + comments.

use std::convert::Infallible;
use std::time::Duration;

use axum::{
    extract::{Path, State},
    response::sse::{Event, KeepAlive, Sse},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use futures_util::stream::{Stream, StreamExt};
use serde::{Deserialize, Serialize};
use tokio_stream::wrappers::BroadcastStream;
use uuid::Uuid;

use crate::{
    auth::AdminContext,
    error::AppError,
    events::{load_existing_steps, make_sse_event},
    state::AppState,
};

/// fixed org used as the jobs.org_id for every internal job. the jobs
/// table requires an org FK, but internal work doesn't belong to a real
/// tenant — this synthetic row exists for referential integrity only.
/// seeded by migration 0004.
const INTERNAL_ORG_ID: Uuid = Uuid::from_u128(0x01900000_0000_7000_8000_000000000fff);

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/youtube", post(create_youtube_ingest))
        .route("/documents", get(list_documents))
        .route("/documents/:id", get(get_document))
        .route("/jobs/:id/events", get(job_events))
}

#[derive(Debug, Deserialize)]
pub struct CreateYoutubeBody {
    pub url: String,
    #[serde(default)]
    pub force: bool,
}

#[derive(Debug, Serialize)]
pub struct CreateYoutubeResponse {
    pub document_id: Uuid,
    pub job_id: Option<Uuid>,
    /// true when an existing non-failed doc was returned without
    /// re-enqueueing. force=true OR previous status='failed' always
    /// flips this back to false.
    pub existing: bool,
}

async fn create_youtube_ingest(
    State(state): State<AppState>,
    _admin: AdminContext,
    Json(body): Json<CreateYoutubeBody>,
) -> Result<Json<CreateYoutubeResponse>, AppError> {
    let url = body.url.trim().to_string();
    if !looks_like_youtube(&url) {
        return Err(AppError::BadRequest(
            "url must be a youtube.com or youtu.be link".into(),
        ));
    }

    // single lookup: is there a top-level youtube doc with this url?
    let existing: Option<(Vec<u8>, String, Option<Vec<u8>>)> = sqlx::query_as(
        "SELECT id, processing_status, job_id FROM documents \
         WHERE source_url = ? AND source_kind = 'youtube' AND source_id IS NULL \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(&url)
    .fetch_optional(&state.pool)
    .await?;

    // dedup short-circuit: non-failed doc + !force → return it as-is.
    if let Some((id_bytes, status, job_bytes)) = &existing {
        if !body.force && status != "failed" {
            let doc_id =
                Uuid::from_slice(id_bytes).map_err(|e| AppError::Internal(e.to_string()))?;
            tracing::info!(
                document_id = %doc_id,
                url = %url,
                "youtube_ingest: returning existing non-failed doc (dedup)"
            );
            return Ok(Json(CreateYoutubeResponse {
                document_id: doc_id,
                job_id: job_bytes
                    .as_deref()
                    .map(Uuid::from_slice)
                    .transpose()
                    .map_err(|e| AppError::Internal(e.to_string()))?,
                existing: true,
            }));
        }
    }

    let now = Utc::now();
    let mut tx = state.pool.begin().await?;

    // determine the doc id we'll work with. branches:
    //   reset path  → existing parent (failed or force=true). delete
    //                 its derived rows, then clear its file fields and
    //                 reset processing_status='queued'.
    //   fresh path  → no existing parent. INSERT new uuid v7.
    let document_id = match &existing {
        Some((id_bytes, _, _)) => {
            let existing_id =
                Uuid::from_slice(id_bytes).map_err(|e| AppError::Internal(e.to_string()))?;

            // derived rows must go first — fk_documents_source would
            // block the parent reset otherwise. cascade-on-delete is
            // overkill; one explicit query is clearer.
            sqlx::query("DELETE FROM documents WHERE source_id = ?")
                .bind(existing_id.as_bytes().as_slice())
                .execute(&mut *tx)
                .await?;

            sqlx::query(
                r#"
                UPDATE documents
                SET bucket=NULL, s3_key=NULL, filename=NULL, mime_type=NULL,
                    duration_ms=NULL, title=NULL,
                    processing_status='queued', processing_error=NULL,
                    updated_at=?
                WHERE id=?
                "#,
            )
            .bind(now)
            .bind(existing_id.as_bytes().as_slice())
            .execute(&mut *tx)
            .await?;

            existing_id
        }
        None => {
            let new_id = Uuid::now_v7();
            sqlx::query(
                r#"
                INSERT INTO documents
                    (id, type, media_kind, source_kind, source_id, source_url,
                     processing_status, created_at, updated_at)
                VALUES (?, 'internal', 'video', 'youtube', NULL, ?, 'queued', ?, ?)
                "#,
            )
            .bind(new_id.as_bytes().as_slice())
            .bind(&url)
            .bind(now)
            .bind(now)
            .execute(&mut *tx)
            .await?;
            new_id
        }
    };

    // enqueue a youtube_ingest job. subject_type='document' marks this
    // as new-shape (vs the old 'internal_media' which referenced the
    // dropped table).
    let job_id = Uuid::now_v7();
    let payload = serde_json::json!({
        "document_id": document_id.to_string(),
        "source_url": url,
    });

    sqlx::query(
        r#"
        INSERT INTO jobs
            (id, org_id, kind, subject_type, subject_id, status, payload, created_at)
        VALUES (?, ?, 'youtube_ingest', 'document', ?, 'queued', ?, ?)
        "#,
    )
    .bind(job_id.as_bytes().as_slice())
    .bind(INTERNAL_ORG_ID.as_bytes().as_slice())
    .bind(document_id.as_bytes().as_slice())
    .bind(serde_json::to_string(&payload).map_err(|e| AppError::Internal(e.to_string()))?)
    .bind(now)
    .execute(&mut *tx)
    .await?;

    sqlx::query("UPDATE documents SET job_id=? WHERE id=?")
        .bind(job_id.as_bytes().as_slice())
        .bind(document_id.as_bytes().as_slice())
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;

    Ok(Json(CreateYoutubeResponse {
        document_id,
        job_id: Some(job_id),
        existing: false,
    }))
}

// matches every column we select from `documents`. `type` is renamed
// to `doc_type` because `type` is a rust reserved keyword; serde
// rewrites it back to "type" on the wire.
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DocumentRow {
    pub id: Uuid,
    #[serde(rename = "type")]
    pub doc_type: String,
    pub media_kind: String,
    pub source_kind: String,
    pub source_id: Option<Uuid>,
    pub source_url: Option<String>,
    pub bucket: Option<String>,
    pub s3_key: Option<String>,
    pub filename: Option<String>,
    pub mime_type: Option<String>,
    pub duration_ms: Option<i32>,
    pub processing_status: String,
    pub processing_error: Option<String>,
    pub job_id: Option<Uuid>,
    pub title: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// json array of StepEvent from the linked job. null when no job.
    pub progress_steps: Option<serde_json::Value>,
}

/// detail response — parent doc + its derived children. the timeline
/// + s3 uri list on the frontend read off this shape.
#[derive(Debug, Serialize)]
pub struct DocumentDetail {
    #[serde(flatten)]
    pub doc: DocumentRow,
    pub derived: Vec<DocumentRow>,
}

// shared SELECT body — the `type AS doc_type` alias keeps rust's
// reserved-keyword issue out of the FromRow derive. LEFT JOIN on
// jobs.id supplies the timeline events for the timeline ui.
const DOCUMENT_SELECT: &str = r#"
    SELECT d.id,
           d.type AS doc_type,
           d.media_kind,
           d.source_kind,
           d.source_id,
           d.source_url,
           d.bucket,
           d.s3_key,
           d.filename,
           d.mime_type,
           d.duration_ms,
           d.processing_status,
           d.processing_error,
           d.job_id,
           d.title,
           d.created_at,
           d.updated_at,
           j.progress_steps
    FROM documents d
    LEFT JOIN jobs j ON j.id = d.job_id
"#;

async fn list_documents(
    State(state): State<AppState>,
    _admin: AdminContext,
) -> Result<Json<Vec<DocumentRow>>, AppError> {
    // list only top-level sources (source_id IS NULL). derived rows
    // appear nested under their parent via GET /documents/:id.
    let sql = format!(
        "{DOCUMENT_SELECT} WHERE d.source_id IS NULL ORDER BY d.created_at DESC LIMIT 200"
    );
    let rows: Vec<DocumentRow> = sqlx::query_as::<_, DocumentRow>(&sql)
        .fetch_all(&state.pool)
        .await?;
    Ok(Json(rows))
}

async fn get_document(
    State(state): State<AppState>,
    _admin: AdminContext,
    Path(id): Path<Uuid>,
) -> Result<Json<Option<DocumentDetail>>, AppError> {
    let doc_sql = format!("{DOCUMENT_SELECT} WHERE d.id = ?");
    let doc: Option<DocumentRow> = sqlx::query_as::<_, DocumentRow>(&doc_sql)
        .bind(id.as_bytes().as_slice())
        .fetch_optional(&state.pool)
        .await?;

    let Some(doc) = doc else {
        return Ok(Json(None));
    };

    // derived list. ordered by filename so the ui shows audio/video in
    // a stable order across reloads.
    let derived_sql = format!(
        "{DOCUMENT_SELECT} WHERE d.source_id = ? ORDER BY d.filename ASC"
    );
    let derived: Vec<DocumentRow> = sqlx::query_as::<_, DocumentRow>(&derived_sql)
        .bind(id.as_bytes().as_slice())
        .fetch_all(&state.pool)
        .await?;

    Ok(Json(Some(DocumentDetail { doc, derived })))
}

// admin-gated mirror of /api/jobs/:id/events. shape identical; the only
// difference is the AdminContext extractor. event encoding + replay
// logic live in events::{load_existing_steps, make_sse_event} so the
// two endpoints can't drift.
async fn job_events(
    State(state): State<AppState>,
    _admin: AdminContext,
    Path(id): Path<Uuid>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    // subscribe BEFORE the db read so events fired in the gap are
    // captured by the tail stream.
    let rx = state.broker.subscribe(id);

    let replay = load_existing_steps(&state, id).await.unwrap_or_default();
    let replay_stream = futures_util::stream::iter(replay.into_iter().map(make_sse_event));

    let tail_stream = BroadcastStream::new(rx)
        .filter_map(|res| async move { res.ok() })
        .map(make_sse_event);

    Sse::new(replay_stream.chain(tail_stream))
        .keep_alive(KeepAlive::new().interval(Duration::from_secs(15)))
}

fn looks_like_youtube(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    (lower.starts_with("http://") || lower.starts_with("https://"))
        && (lower.contains("youtube.com/")
            || lower.contains("youtu.be/")
            || lower.contains("music.youtube.com/"))
}
