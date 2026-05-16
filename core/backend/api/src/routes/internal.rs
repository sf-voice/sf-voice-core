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
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter, QueryOrder,
    QuerySelect, TransactionTrait,
};
use serde::{Deserialize, Serialize};
use tokio_stream::wrappers::BroadcastStream;
use uuid::Uuid;

use crate::{
    auth::AdminContext,
    error::AppError,
    events::{load_existing_steps, make_sse_event},
    state::AppState,
};

const INTERNAL_ORG_ID: Uuid = Uuid::from_u128(0x01900000_0000_7000_8000_000000000fff);

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/youtube", post(create_youtube_ingest))
        .route("/documents", get(list_documents))
        .route("/documents/:id", get(get_document))
        .route("/documents/:id/retry", post(retry_document))
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

    // check is there a top-level youtube doc with this url?
    let existing = entities::documents::Entity::find()
        .filter(entities::documents::Column::SourceUrl.eq(url.clone()))
        .filter(entities::documents::Column::SourceKind.eq("youtube"))
        .filter(entities::documents::Column::SourceId.is_null())
        .order_by_desc(entities::documents::Column::CreatedAt)
        .one(&state.orm)
        .await?;

    // dedup short-circuit: non-failed doc + !force → return it as-is.
    if let Some(ref existing) = existing {
        if !body.force && existing.processing_status != "failed" {
            let doc_id =
                Uuid::from_slice(&existing.id).map_err(|e| AppError::Internal(e.to_string()))?;
            tracing::info!(
                document_id = %doc_id,
                url = %url,
                "youtube_ingest: returning existing non-failed doc (dedup)"
            );
            let job_id = existing
                .job_id
                .as_deref()
                .map(Uuid::from_slice)
                .transpose()
                .map_err(|e| AppError::Internal(e.to_string()))?;
            return Ok(Json(CreateYoutubeResponse {
                document_id: doc_id,
                job_id,
                existing: true,
            }));
        }
    }

    let txn = state.orm.begin().await?;

    let document_id = match existing {
        Some(existing) => {
            let existing_id =
                Uuid::from_slice(&existing.id).map_err(|e| AppError::Internal(e.to_string()))?;

            // derived rows must go first — fk_documents_source would
            // block the parent reset otherwise. cascade-on-delete is
            // overkill; one explicit delete is clearer.
            entities::documents::Entity::delete_many()
                .filter(entities::documents::Column::SourceId.eq(existing.id.clone()))
                .exec(&txn)
                .await?;

            entities::documents::ActiveModel {
                id: Set(existing.id.clone()),
                bucket: Set(None),
                s3_key: Set(None),
                filename: Set(None),
                mime_type: Set(None),
                duration_ms: Set(None),
                title: Set(None),
                processing_status: Set("queued".into()),
                processing_error: Set(None),
                ..Default::default()
            }
            .update(&txn)
            .await?;

            existing_id
        }
        None => {
            let new_id = Uuid::now_v7();
            entities::documents::ActiveModel {
                id: Set(new_id.as_bytes().to_vec()),
                r#type: Set("internal".into()),
                media_kind: Set("video".into()),
                source_kind: Set("youtube".into()),
                source_id: Set(None),
                source_url: Set(Some(url.clone())),
                processing_status: Set("queued".into()),
                ..Default::default()
            }
            .insert(&txn)
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

    entities::jobs::ActiveModel {
        id: Set(job_id.as_bytes().to_vec()),
        org_id: Set(INTERNAL_ORG_ID.as_bytes().to_vec()),
        kind: Set("youtube_ingest".into()),
        subject_type: Set("document".into()),
        subject_id: Set(Some(document_id.as_bytes().to_vec())),
        status: Set("queued".into()),
        payload: Set(Some(payload)),
        ..Default::default()
    }
    .insert(&txn)
    .await?;

    entities::documents::ActiveModel {
        id: Set(document_id.as_bytes().to_vec()),
        job_id: Set(Some(job_id.as_bytes().to_vec())),
        ..Default::default()
    }
    .update(&txn)
    .await?;

    txn.commit().await?;

    Ok(Json(CreateYoutubeResponse {
        document_id,
        job_id: Some(job_id),
        existing: false,
    }))
}

#[derive(Debug, Serialize)]
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

fn document_row(
    m: entities::documents::Model,
    progress_steps: Option<serde_json::Value>,
) -> DocumentRow {
    DocumentRow {
        id: Uuid::from_slice(&m.id).expect("documents.id is BINARY(16)"),
        doc_type: m.r#type,
        media_kind: m.media_kind,
        source_kind: m.source_kind,
        source_id: m.source_id.as_deref().map(|b| Uuid::from_slice(b).unwrap()),
        source_url: m.source_url,
        bucket: m.bucket,
        s3_key: m.s3_key,
        filename: m.filename,
        mime_type: m.mime_type,
        duration_ms: m.duration_ms,
        processing_status: m.processing_status,
        processing_error: m.processing_error,
        job_id: m.job_id.as_deref().map(|b| Uuid::from_slice(b).unwrap()),
        title: m.title,
        created_at: DateTime::<Utc>::from_naive_utc_and_offset(m.created_at, Utc),
        updated_at: DateTime::<Utc>::from_naive_utc_and_offset(m.updated_at, Utc),
        progress_steps,
    }
}

async fn progress_for_jobs(
    state: &AppState,
    job_ids: Vec<Vec<u8>>,
) -> Result<std::collections::HashMap<Vec<u8>, serde_json::Value>, AppError> {
    if job_ids.is_empty() {
        return Ok(Default::default());
    }
    let jobs = entities::jobs::Entity::find()
        .filter(entities::jobs::Column::Id.is_in(job_ids))
        .all(&state.orm)
        .await?;
    Ok(jobs
        .into_iter()
        .filter_map(|j| j.progress_steps.map(|p| (j.id, p)))
        .collect())
}

async fn list_documents(
    State(state): State<AppState>,
    _admin: AdminContext,
) -> Result<Json<Vec<DocumentRow>>, AppError> {
    // list only top-level sources (source_id IS NULL). derived rows
    // appear nested under their parent via GET /documents/:id.
    let docs = entities::documents::Entity::find()
        .filter(entities::documents::Column::SourceId.is_null())
        .order_by_desc(entities::documents::Column::CreatedAt)
        .limit(200)
        .all(&state.orm)
        .await?;

    let job_ids: Vec<Vec<u8>> = docs.iter().filter_map(|d| d.job_id.clone()).collect();
    let progress = progress_for_jobs(&state, job_ids).await?;

    let rows = docs
        .into_iter()
        .map(|d| {
            let p = d.job_id.as_ref().and_then(|id| progress.get(id).cloned());
            document_row(d, p)
        })
        .collect();
    Ok(Json(rows))
}

/// soft retry: re-enqueue a youtube_ingest job for an existing failed
/// document without wiping derived rows or the parent's metadata. the
/// job itself is idempotent — already-downloaded files on disk + already
/// -uploaded objects on s3 are skipped (see `youtube_ingest::run_steps`).
/// returns the new job_id so the frontend can swap its SSE subscription.
async fn retry_document(
    State(state): State<AppState>,
    _admin: AdminContext,
    Path(id): Path<Uuid>,
) -> Result<Json<CreateYoutubeResponse>, AppError> {
    let doc = entities::documents::Entity::find_by_id(id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or_else(|| AppError::BadRequest("document not found".into()))?;

    if doc.source_kind != "youtube" {
        return Err(AppError::BadRequest(
            "retry only supports youtube documents for now".into(),
        ));
    }
    if doc.processing_status != "failed" {
        return Err(AppError::BadRequest(format!(
            "retry only allowed on failed docs (current: {})",
            doc.processing_status
        )));
    }
    let source_url = doc
        .source_url
        .clone()
        .ok_or_else(|| AppError::Internal("failed youtube doc has no source_url".into()))?;

    let txn = state.orm.begin().await?;

    let job_id = Uuid::now_v7();
    let payload = serde_json::json!({
        "document_id": id.to_string(),
        "source_url": source_url,
    });
    entities::jobs::ActiveModel {
        id: Set(job_id.as_bytes().to_vec()),
        org_id: Set(INTERNAL_ORG_ID.as_bytes().to_vec()),
        kind: Set("youtube_ingest".into()),
        subject_type: Set("document".into()),
        subject_id: Set(Some(id.as_bytes().to_vec())),
        status: Set("queued".into()),
        payload: Set(Some(payload)),
        ..Default::default()
    }
    .insert(&txn)
    .await?;

    // flip parent back to 'queued' + clear the failure marker; the
    // running ingest job will overwrite this as it moves through steps.
    // we deliberately do NOT delete derived rows or wipe bucket/s3_key —
    // the idempotent job will skip uploads of objects that already exist.
    entities::documents::ActiveModel {
        id: Set(id.as_bytes().to_vec()),
        job_id: Set(Some(job_id.as_bytes().to_vec())),
        processing_status: Set("queued".into()),
        processing_error: Set(None),
        ..Default::default()
    }
    .update(&txn)
    .await?;

    txn.commit().await?;

    Ok(Json(CreateYoutubeResponse {
        document_id: id,
        job_id: Some(job_id),
        existing: false,
    }))
}

async fn get_document(
    State(state): State<AppState>,
    _admin: AdminContext,
    Path(id): Path<Uuid>,
) -> Result<Json<Option<DocumentDetail>>, AppError> {
    let doc = entities::documents::Entity::find_by_id(id.as_bytes().to_vec())
        .one(&state.orm)
        .await?;
    let Some(doc) = doc else {
        return Ok(Json(None));
    };

    let derived = entities::documents::Entity::find()
        .filter(entities::documents::Column::SourceId.eq(doc.id.clone()))
        .order_by_asc(entities::documents::Column::Filename)
        .all(&state.orm)
        .await?;

    let mut job_ids: Vec<Vec<u8>> = Vec::new();
    if let Some(j) = doc.job_id.clone() {
        job_ids.push(j);
    }
    for d in &derived {
        if let Some(j) = d.job_id.clone() {
            job_ids.push(j);
        }
    }
    let progress = progress_for_jobs(&state, job_ids).await?;

    let parent_progress = doc.job_id.as_ref().and_then(|id| progress.get(id).cloned());
    let parent = document_row(doc, parent_progress);

    let derived = derived
        .into_iter()
        .map(|d| {
            let p = d.job_id.as_ref().and_then(|id| progress.get(id).cloned());
            document_row(d, p)
        })
        .collect();

    Ok(Json(Some(DocumentDetail {
        doc: parent,
        derived,
    })))
}

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
