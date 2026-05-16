//! /api/jobs — job rows + sse stream for the reasoning-path panel.
//!
//! the sse handler replays `jobs.progress_steps` on connect (so a
//! late subscriber gets every step that already happened) and then
//! tails the in-process broadcast channel for new ones.

use std::convert::Infallible;
use std::time::Duration;

use axum::{
    extract::{Path, State},
    response::sse::{Event, KeepAlive, Sse},
    routing::get,
    Json, Router,
};
use chrono::{DateTime, Utc};
use futures_util::stream::{Stream, StreamExt};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use tokio_stream::wrappers::BroadcastStream;
use uuid::Uuid;

use crate::{
    error::AppError,
    events::{load_existing_steps, make_sse_event},
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/jobs/:id", get(get_job))
        .route("/jobs/:id/events", get(job_events))
}

#[derive(Debug, serde::Serialize)]
pub struct JobRow {
    pub id: Uuid,
    pub kind: String,
    pub status: String,
    pub progress_steps: serde_json::Value,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub finished_at: Option<DateTime<Utc>>,
    pub pr_url: Option<String>,
}

async fn get_job(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Option<JobRow>>, AppError> {
    let id_bytes = id.as_bytes().to_vec();
    let job = entities::jobs::Entity::find_by_id(id_bytes.clone())
        .one(&state.orm)
        .await?;
    let Some(job) = job else {
        return Ok(Json(None));
    };

    // pr_url comes from the linked prompt_slice (if this is a sandbox
    // job). the FK direction is slice → job, so look up slice by job_id.
    let slice = entities::prompt_slices::Entity::find()
        .filter(entities::prompt_slices::Column::JobId.eq(id_bytes))
        .one(&state.orm)
        .await?;
    let pr_url = slice.and_then(|s| s.pr_url);

    Ok(Json(Some(JobRow {
        id,
        kind: job.kind,
        status: job.status,
        progress_steps: job
            .progress_steps
            .unwrap_or(serde_json::Value::Array(vec![])),
        error_message: job.error_message,
        created_at: DateTime::<Utc>::from_naive_utc_and_offset(job.created_at, Utc),
        started_at: job
            .started_at
            .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
        finished_at: job
            .finished_at
            .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
        pr_url,
    })))
}

async fn job_events(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    // subscribe BEFORE reading the db so we don't miss events fired in
    // the window between read and stream-start.
    let rx = state.broker.subscribe(id);

    let replay = load_existing_steps(&state, id).await.unwrap_or_default();
    let replay_stream = futures_util::stream::iter(replay.into_iter().map(make_sse_event));

    let tail_stream = BroadcastStream::new(rx)
        // skip errors silently (lagged subscribers); db replay covers
        // the gap if the client reconnects.
        .filter_map(|res| async move { res.ok() })
        .map(make_sse_event);

    let combined = replay_stream.chain(tail_stream);

    Sse::new(combined).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)))
}
