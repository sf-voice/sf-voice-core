use std::time::Duration;

use sea_orm::{
    sea_query::Expr, ActiveModelTrait, ActiveValue::Set, ColumnTrait, DatabaseConnection,
    EntityTrait, QueryFilter, QueryOrder,
};
use uuid::Uuid;

use crate::{
    error::AppError,
    models::{StepEvent, StepStatus},
    slack,
    state::AppState,
};

pub mod ingest;
pub mod sandbox_stub;
pub mod transcribe;
pub mod transcribe_document;
pub mod youtube_ingest;

const POLL_INTERVAL: Duration = Duration::from_millis(500);

pub async fn run(state: AppState) {
    tracing::info!("job runner started");
    loop {
        match claim_one(&state.orm).await {
            Ok(Some((job_id, kind, org_id, payload))) => {
                tracing::info!(%job_id, %kind, "job claimed");
                let result = dispatch(&state, job_id, &kind, org_id, payload).await;
                if let Err(e) = &result {
                    tracing::error!(%job_id, %kind, error = %e, "job failed");
                }
                if let Err(e) = mark_finished(&state.orm, job_id, &result).await {
                    tracing::error!(%job_id, ?e, "failed to mark job finished");
                }
                state.broker.close(job_id);
            }
            Ok(None) => {
                tokio::time::sleep(POLL_INTERVAL).await;
            }
            Err(e) => {
                tracing::error!(?e, "claim_one failed");
                tokio::time::sleep(POLL_INTERVAL).await;
            }
        }
    }
}

async fn claim_one(
    db: &DatabaseConnection,
) -> Result<Option<(Uuid, String, Uuid, Option<serde_json::Value>)>, AppError> {
    let pick = entities::jobs::Entity::find()
        .filter(entities::jobs::Column::Status.eq("queued"))
        .order_by_asc(entities::jobs::Column::CreatedAt)
        .one(db)
        .await?;
    let Some(job) = pick else {
        return Ok(None);
    };

    let updated = entities::jobs::Entity::update_many()
        .col_expr(entities::jobs::Column::Status, Expr::value("running"))
        .col_expr(
            entities::jobs::Column::StartedAt,
            Expr::current_timestamp().into(),
        )
        .filter(entities::jobs::Column::Id.eq(job.id.clone()))
        .filter(entities::jobs::Column::Status.eq("queued"))
        .exec(db)
        .await?;
    if updated.rows_affected == 0 {
        return Ok(None);
    }

    let id = Uuid::from_slice(&job.id).map_err(|e| AppError::Internal(e.to_string()))?;
    let org_id = Uuid::from_slice(&job.org_id).map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Some((id, job.kind, org_id, job.payload)))
}

async fn dispatch(
    state: &AppState,
    job_id: Uuid,
    kind: &str,
    org_id: Uuid,
    payload: Option<serde_json::Value>,
) -> Result<(), AppError> {
    match kind {
        "sandbox" => sandbox_stub::run(state, job_id, org_id, payload).await,
        "ingest" => ingest::run(state, job_id, org_id, payload).await,
        "transcribe" => transcribe::run(state, job_id, org_id, payload).await,
        "transcribe_document" => transcribe_document::run(state, job_id, org_id, payload).await,
        "youtube_ingest" => youtube_ingest::run(state, job_id, org_id, payload).await,
        "open_pr" => Err(AppError::Internal(
            "'open_pr' is bundled into the sandbox stub for v1 — should never be enqueued separately".into(),
        )),
        other => Err(AppError::Internal(format!("unknown job kind: {other}"))),
    }
}

async fn mark_finished(
    db: &DatabaseConnection,
    job_id: Uuid,
    result: &Result<(), AppError>,
) -> Result<(), AppError> {
    let (status, error) = match result {
        Ok(()) => ("done", None),
        Err(e) => ("failed", Some(e.to_string())),
    };
    entities::jobs::Entity::update_many()
        .col_expr(entities::jobs::Column::Status, Expr::value(status))
        .col_expr(
            entities::jobs::Column::FinishedAt,
            Expr::current_timestamp().into(),
        )
        .col_expr(entities::jobs::Column::ErrorMessage, Expr::value(error))
        .filter(entities::jobs::Column::Id.eq(job_id.as_bytes().to_vec()))
        .exec(db)
        .await?;
    Ok(())
}

pub async fn append_step(
    state: &AppState,
    org_id: Uuid,
    job_id: Uuid,
    step: &str,
    status: StepStatus,
    detail: Option<String>,
) -> Result<StepEvent, AppError> {
    tracing::info!(
        %job_id,
        step,
        ?status,
        detail = detail.as_deref().unwrap_or(""),
        "step"
    );

    let event = StepEvent {
        step: step.to_string(),
        status,
        ts: chrono::Utc::now(),
        detail,
    };

    let job_id_bytes = job_id.as_bytes().to_vec();
    let job = entities::jobs::Entity::find_by_id(job_id_bytes.clone())
        .one(&state.orm)
        .await?
        .ok_or_else(|| AppError::Internal(format!("job {job_id} not found")))?;

    let mut steps: Vec<StepEvent> = job
        .progress_steps
        .as_ref()
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();
    steps.push(event.clone());
    let new_steps = serde_json::to_value(&steps).map_err(|e| AppError::Internal(e.to_string()))?;

    entities::jobs::ActiveModel {
        id: Set(job_id_bytes),
        progress_steps: Set(Some(new_steps)),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;

    state.broker.publish(job_id, event.clone());

    let org = entities::orgs::Entity::find_by_id(org_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?;
    if let Some(url) = org.and_then(|o| o.slack_webhook_url) {
        let id_str = job_id.to_string();
        slack::post_step(&state.http, &url, &id_str, &event).await;
    }

    Ok(event)
}
