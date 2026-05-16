//! sandbox-stub job: walks the seven canonical step events with sleeps
//! between them. final step writes a placeholder pr_url onto the
//! prompt_slices row and flips its status to 'pr_open'.

use std::time::Duration;

use sea_orm::{ActiveModelTrait, ActiveValue::Set, DatabaseConnection, EntityTrait};
use uuid::Uuid;

use crate::{error::AppError, jobs::append_step, models::StepStatus, state::AppState};

/// the canonical step list. order is contract; phrasing is cosmetic.
/// TODO: change step to identifiders snake_case
const STEPS: &[&str] = &[
    "slice captured",
    "context assembled",
    "sandbox provisioned",
    "regenerating AI response",
    "rendering TTS audio",
    "opening PR",
    "awaiting review",
];

/// per-step dwell time. tuned so the reasoning-path panel feels alive
/// without crawling. ~12s total.
const STEP_DWELL: Duration = Duration::from_millis(1700);

pub async fn run(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    payload: Option<serde_json::Value>,
) -> Result<(), AppError> {
    let slice_id = payload
        .as_ref()
        .and_then(|p| p.get("slice_id"))
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(|| AppError::Internal("sandbox job missing slice_id in payload".into()))?;

    for (idx, step) in STEPS.iter().enumerate() {
        append_step(state, org_id, job_id, step, StepStatus::Running, None).await?;
        tokio::time::sleep(STEP_DWELL).await;

        // last step: side-effects (status flip + placeholder pr_url) go
        // here so the 'done' event the frontend renders reflects the
        // real terminal state of the slice.
        if idx == STEPS.len() - 1 {
            let pr_url = placeholder_pr_url(&state.orm, org_id).await?;
            entities::prompt_slices::ActiveModel {
                id: Set(slice_id.as_bytes().to_vec()),
                status: Set("pr_open".into()),
                pr_url: Set(Some(pr_url.clone())),
                ..Default::default()
            }
            .update(&state.orm)
            .await?;
            append_step(
                state,
                org_id,
                job_id,
                step,
                StepStatus::Done,
                Some(format!("PR opened: {pr_url}")),
            )
            .await?;
        } else {
            append_step(state, org_id, job_id, step, StepStatus::Done, None).await?;
        }
    }

    Ok(())
}

async fn placeholder_pr_url(db: &DatabaseConnection, org_id: Uuid) -> Result<String, AppError> {
    let org = entities::orgs::Entity::find_by_id(org_id.as_bytes().to_vec())
        .one(db)
        .await?;
    let slug = org.map(|o| o.slug).unwrap_or_else(|| "unknown".to_string());
    Ok(format!("https://github.com/sf-voice/cfg-{slug}/pull/0"))
}
