//! ingest job: list a customer's S3 prefix → create one `calls` row per
//! audio file we haven't seen before → enqueue a `transcribe` job for
//! each. idempotency is by `calls.audio_uri` — the `files` inventory
//! table was redundant once `documents` + `calls.audio_uri` existed.
//!
//! audio detection is by extension for v1 — wav, mp3, m4a, flac, ogg.
//! customers who store with weird names should rename or set a prefix.

use std::time::Duration;

use chrono::{DateTime, Utc};
use sea_orm::{ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter};
use uuid::Uuid;

use crate::{aws_creds, error::AppError, jobs::append_step, models::StepStatus, state::AppState};

const AUDIO_EXTS: &[&str] = &["wav", "mp3", "m4a", "flac", "ogg", "webm"];

pub async fn run(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    _payload: Option<serde_json::Value>,
) -> Result<(), AppError> {
    append_step(
        state,
        org_id,
        job_id,
        "resolving credentials",
        StepStatus::Running,
        None,
    )
    .await?;

    let bucket = aws_creds::open_for_org(&state.orm, org_id).await?;

    append_step(
        state,
        org_id,
        job_id,
        "resolving credentials",
        StepStatus::Done,
        Some(format!("s3://{}/{}", bucket.bucket, bucket.prefix)),
    )
    .await?;

    append_step(
        state,
        org_id,
        job_id,
        "listing bucket",
        StepStatus::Running,
        None,
    )
    .await?;

    // single page is fine for v1. paginate when customers cross 1000
    // objects in a single ingest.
    let resp = bucket
        .s3
        .list_objects_v2()
        .bucket(&bucket.bucket)
        .prefix(bucket.prefix.trim_start_matches('/'))
        .max_keys(1000)
        .send()
        .await
        .map_err(|e| AppError::BadRequest(format!("S3 ListObjects: {e}")))?;

    let objects = resp.contents.unwrap_or_default();
    let total = objects.len();

    append_step(
        state,
        org_id,
        job_id,
        "listing bucket",
        StepStatus::Done,
        Some(format!(
            "{total} object{} discovered",
            if total == 1 { "" } else { "s" }
        )),
    )
    .await?;

    let mut transcribe_jobs = 0;
    for obj in objects {
        let Some(key) = obj.key else { continue };
        if !is_audio(&key) {
            continue;
        }
        let last_modified = obj
            .last_modified
            .and_then(|t| DateTime::<Utc>::from_timestamp(t.secs(), 0))
            .map(|t| t.naive_utc());

        let now = Utc::now().naive_utc();
        let audio_uri = format!("s3://{}/{}", bucket.bucket, key);

        // dedupe by audio_uri — if a call already exists for this s3
        // object, skip. re-transcribing happens via the explicit
        // /calls/:id/transcribe-runs endpoint, not by re-listing.
        let existing = entities::calls::Entity::find()
            .filter(entities::calls::Column::OrgId.eq(org_id.as_bytes().to_vec()))
            .filter(entities::calls::Column::AudioUri.eq(audio_uri.clone()))
            .one(&state.orm)
            .await?;
        if existing.is_some() {
            continue;
        }

        let call_id = Uuid::now_v7();
        entities::calls::ActiveModel {
            id: Set(call_id.as_bytes().to_vec()),
            org_id: Set(org_id.as_bytes().to_vec()),
            started_at: Set(last_modified.unwrap_or(now)),
            audio_uri: Set(Some(audio_uri.clone())),
            caller_audio_uri: Set(Some(audio_uri.clone())),
            ai_audio_uri: Set(Some(audio_uri)),
            duration_ms: Set(None),
            ..Default::default()
        }
        .insert(&state.orm)
        .await?;

        // enqueue transcribe.
        let t_job = Uuid::now_v7();
        entities::jobs::ActiveModel {
            id: Set(t_job.as_bytes().to_vec()),
            org_id: Set(org_id.as_bytes().to_vec()),
            kind: Set("transcribe".into()),
            subject_type: Set("call".into()),
            subject_id: Set(Some(call_id.as_bytes().to_vec())),
            status: Set("queued".into()),
            payload: Set(Some(serde_json::json!({ "call_id": call_id.to_string() }))),
            ..Default::default()
        }
        .insert(&state.orm)
        .await?;

        transcribe_jobs += 1;
        // tiny breath between enqueues so the runner can pick them up
        // and start showing progress in the ui while we keep listing.
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    append_step(
        state,
        org_id,
        job_id,
        "enqueuing transcribe jobs",
        StepStatus::Done,
        Some(format!(
            "{transcribe_jobs} new audio file{}",
            if transcribe_jobs == 1 { "" } else { "s" }
        )),
    )
    .await?;

    Ok(())
}

fn is_audio(key: &str) -> bool {
    let lower = key.to_lowercase();
    AUDIO_EXTS
        .iter()
        .any(|ext| lower.ends_with(&format!(".{ext}")))
}
