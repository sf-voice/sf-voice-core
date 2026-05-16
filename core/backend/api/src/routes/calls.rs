//! /api/calls — the debugger's primary read surface + slice + retranscribe
//! creators.

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter, QueryOrder,
    QuerySelect, TransactionTrait,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{error::AppError, models::Call, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/calls", get(list_calls))
        .route("/calls/:id", get(get_call))
        .route("/calls/:id/transcripts", get(list_transcripts))
        .route("/calls/:id/slices", post(create_slice))
        .route("/calls/:id/transcribe-runs", post(create_transcribe_run))
}

async fn list_calls(
    State(state): State<AppState>,
    auth: crate::auth::AuthContext,
) -> Result<Json<Vec<Call>>, AppError> {
    let rows = entities::calls::Entity::find()
        .filter(entities::calls::Column::OrgId.eq(auth.current_org_id.as_bytes().to_vec()))
        .order_by_desc(entities::calls::Column::StartedAt)
        .limit(200)
        .all(&state.orm)
        .await?;
    Ok(Json(rows.into_iter().map(Call::from).collect()))
}

async fn get_call(
    State(state): State<AppState>,
    auth: crate::auth::AuthContext,
    Path(id): Path<Uuid>,
) -> Result<Json<Option<Call>>, AppError> {
    let row = entities::calls::Entity::find_by_id(id.as_bytes().to_vec())
        .filter(entities::calls::Column::OrgId.eq(auth.current_org_id.as_bytes().to_vec()))
        .one(&state.orm)
        .await?
        .map(Call::from);
    Ok(Json(row))
}

#[derive(Debug, Serialize)]
pub struct TranscriptRow {
    pub id: i64,
    pub call_id: Uuid,
    pub speaker_label: String,
    pub start_ms: i32,
    pub end_ms: i32,
    pub text: String,
    pub confidence: Option<f32>,
    pub model_version: String,
}

async fn list_transcripts(
    State(state): State<AppState>,
    auth: crate::auth::AuthContext,
    Path(id): Path<Uuid>,
) -> Result<Json<Vec<TranscriptRow>>, AppError> {
    let call_id_bytes = id.as_bytes().to_vec();
    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();

    // verify call belongs to this org. cheap check that doubles as a 404
    // path so we don't leak transcripts cross-tenant.
    let call_owned = entities::calls::Entity::find_by_id(call_id_bytes.clone())
        .filter(entities::calls::Column::OrgId.eq(org_id_bytes))
        .one(&state.orm)
        .await?;
    if call_owned.is_none() {
        return Err(AppError::NotFound);
    }

    // transcripts table holds only the canonical (latest) run — re-runs
    // are delete-then-insert in the transcribe job.
    let rows = entities::transcripts::Entity::find()
        .filter(entities::transcripts::Column::CallId.eq(call_id_bytes))
        .order_by_asc(entities::transcripts::Column::StartMs)
        .all(&state.orm)
        .await?;

    let out = rows
        .into_iter()
        .map(|t| TranscriptRow {
            id: t.id,
            call_id: Uuid::from_slice(t.call_id.as_deref().expect("call-route row has call_id"))
                .expect("transcripts.call_id BINARY(16)"),
            speaker_label: t.speaker_label,
            start_ms: t.start_ms,
            end_ms: t.end_ms,
            text: t.text,
            confidence: t.confidence,
            model_version: t.model_version,
        })
        .collect();

    Ok(Json(out))
}

#[derive(Debug, Deserialize)]
pub struct CreateSliceBody {
    pub start_ms: i32,
    pub end_ms: i32,
    pub prompt_text: String,
}

#[derive(Debug, Serialize)]
pub struct CreateSliceResponse {
    pub slice_id: Uuid,
    pub job_id: Uuid,
}

async fn create_slice(
    State(state): State<AppState>,
    auth: crate::auth::AuthContext,
    Path(call_id): Path<Uuid>,
    Json(body): Json<CreateSliceBody>,
) -> Result<Json<CreateSliceResponse>, AppError> {
    if body.end_ms <= body.start_ms {
        return Err(AppError::BadRequest("end_ms must be > start_ms".into()));
    }
    if body.prompt_text.trim().is_empty() {
        return Err(AppError::BadRequest("prompt_text required".into()));
    }

    let call_id_bytes = call_id.as_bytes().to_vec();
    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();

    // verify call belongs to this org.
    let owned = entities::calls::Entity::find_by_id(call_id_bytes.clone())
        .filter(entities::calls::Column::OrgId.eq(org_id_bytes.clone()))
        .one(&state.orm)
        .await?;
    if owned.is_none() {
        return Err(AppError::NotFound);
    }

    let slice_id = Uuid::now_v7();
    let job_id = Uuid::now_v7();
    let payload = serde_json::json!({ "slice_id": slice_id.to_string() });

    let txn = state.orm.begin().await?;

    // job first so the slice's FK reference resolves on insert.
    entities::jobs::ActiveModel {
        id: Set(job_id.as_bytes().to_vec()),
        org_id: Set(org_id_bytes.clone()),
        kind: Set("sandbox".into()),
        subject_type: Set("slice".into()),
        subject_id: Set(Some(slice_id.as_bytes().to_vec())),
        status: Set("queued".into()),
        payload: Set(Some(payload)),
        ..Default::default()
    }
    .insert(&txn)
    .await?;

    entities::prompt_slices::ActiveModel {
        id: Set(slice_id.as_bytes().to_vec()),
        call_id: Set(call_id_bytes),
        org_id: Set(org_id_bytes),
        start_ms: Set(body.start_ms),
        end_ms: Set(body.end_ms),
        prompt_text: Set(body.prompt_text),
        status: Set("sandboxed".into()),
        job_id: Set(Some(job_id.as_bytes().to_vec())),
        ..Default::default()
    }
    .insert(&txn)
    .await?;

    txn.commit().await?;

    Ok(Json(CreateSliceResponse { slice_id, job_id }))
}

#[derive(Debug, Serialize)]
pub struct CreateTranscribeRunResponse {
    pub job_id: Uuid,
}

async fn create_transcribe_run(
    State(state): State<AppState>,
    auth: crate::auth::AuthContext,
    Path(call_id): Path<Uuid>,
) -> Result<Json<CreateTranscribeRunResponse>, AppError> {
    let call_id_bytes = call_id.as_bytes().to_vec();
    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();

    let owned = entities::calls::Entity::find_by_id(call_id_bytes.clone())
        .filter(entities::calls::Column::OrgId.eq(org_id_bytes.clone()))
        .one(&state.orm)
        .await?;
    if owned.is_none() {
        return Err(AppError::NotFound);
    }

    let job_id = Uuid::now_v7();
    let payload = serde_json::json!({ "call_id": call_id.to_string() });

    entities::jobs::ActiveModel {
        id: Set(job_id.as_bytes().to_vec()),
        org_id: Set(org_id_bytes),
        kind: Set("transcribe".into()),
        subject_type: Set("call".into()),
        subject_id: Set(Some(call_id_bytes)),
        status: Set("queued".into()),
        payload: Set(Some(payload)),
        ..Default::default()
    }
    .insert(&state.orm)
    .await?;

    Ok(Json(CreateTranscribeRunResponse { job_id }))
}
