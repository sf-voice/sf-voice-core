//! API DTOs for the debugging product. shape == json wire format.
//! handlers convert from `entities::*::Model` via the `From` impls below.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// helper: BINARY(16) bytes → Uuid. infallible at the boundary because
// the schema enforces 16-byte width on every BINARY(16) column.
fn uuid_from_bytes(b: &[u8]) -> Uuid {
    Uuid::from_slice(b).expect("BINARY(16) → uuid")
}

/// json shape for an entry in `jobs.progress_steps` and for sse events.
/// the frontend reasoning-path component renders one of these per row.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepEvent {
    pub step: String,
    pub status: StepStatus,
    pub ts: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StepStatus {
    Pending,
    Running,
    Done,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
pub struct Org {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub bucket_name: Option<String>,
    pub bucket_prefix: Option<String>,
    pub bucket_region: Option<String>,
    pub bucket_role_arn: Option<String>,
    pub bucket_external_id: Option<String>,
    pub config_repo_url: Option<String>,
    pub slack_webhook_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Call {
    pub id: Uuid,
    pub org_id: Uuid,
    pub external_id: Option<String>,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub duration_ms: Option<i32>,
    pub caller_number: Option<String>,
    pub destination_number: Option<String>,
    pub termination_reason: Option<String>,
    pub audio_uri: Option<String>,
    pub caller_audio_uri: Option<String>,
    pub ai_audio_uri: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Transcript {
    pub id: i64,
    pub call_id: Uuid,
    pub run_id: Uuid,
    /// 'ai' | 'caller' | 'unknown' — stored as enum in mysql, surfaced
    /// as a free string here. cast at the api boundary if a typed enum
    /// becomes worth it.
    pub speaker_label: String,
    pub start_ms: i32,
    pub end_ms: i32,
    pub text: String,
    pub confidence: Option<f32>,
    pub model_version: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Job {
    pub id: Uuid,
    pub org_id: Uuid,
    pub kind: String,
    pub subject_type: String,
    pub subject_id: Option<Uuid>,
    pub status: String,
    pub payload: Option<serde_json::Value>,
    pub result: Option<serde_json::Value>,
    pub error_message: Option<String>,
    pub progress_steps: Option<serde_json::Value>,
    pub slack_thread_ts: Option<String>,
    pub created_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub finished_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PromptSlice {
    pub id: Uuid,
    pub call_id: Uuid,
    pub org_id: Uuid,
    pub start_ms: i32,
    pub end_ms: i32,
    pub prompt_text: String,
    pub status: String,
    pub job_id: Option<Uuid>,
    pub pr_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<entities::calls::Model> for Call {
    fn from(m: entities::calls::Model) -> Self {
        Self {
            id: uuid_from_bytes(&m.id),
            org_id: uuid_from_bytes(&m.org_id),
            external_id: m.external_id,
            started_at: DateTime::<Utc>::from_naive_utc_and_offset(m.started_at, Utc),
            ended_at: m
                .ended_at
                .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
            duration_ms: m.duration_ms,
            caller_number: m.caller_number,
            destination_number: m.destination_number,
            termination_reason: m.termination_reason,
            audio_uri: m.audio_uri,
            caller_audio_uri: m.caller_audio_uri,
            ai_audio_uri: m.ai_audio_uri,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(m.created_at, Utc),
            updated_at: DateTime::<Utc>::from_naive_utc_and_offset(m.updated_at, Utc),
        }
    }
}

impl From<entities::orgs::Model> for Org {
    fn from(m: entities::orgs::Model) -> Self {
        Self {
            id: uuid_from_bytes(&m.id),
            name: m.name,
            slug: m.slug,
            bucket_name: m.bucket_name,
            bucket_prefix: m.bucket_prefix,
            bucket_region: m.bucket_region,
            bucket_role_arn: m.bucket_role_arn,
            bucket_external_id: m.bucket_external_id,
            config_repo_url: m.config_repo_url,
            slack_webhook_url: m.slack_webhook_url,
            // entities use chrono::NaiveDateTime; assume UTC at the boundary.
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(m.created_at, Utc),
            updated_at: DateTime::<Utc>::from_naive_utc_and_offset(m.updated_at, Utc),
        }
    }
}

impl From<entities::prompt_slices::Model> for PromptSlice {
    fn from(m: entities::prompt_slices::Model) -> Self {
        Self {
            id: uuid_from_bytes(&m.id),
            call_id: uuid_from_bytes(&m.call_id),
            org_id: uuid_from_bytes(&m.org_id),
            start_ms: m.start_ms,
            end_ms: m.end_ms,
            prompt_text: m.prompt_text,
            status: m.status,
            job_id: m.job_id.as_deref().map(uuid_from_bytes),
            pr_url: m.pr_url,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(m.created_at, Utc),
            updated_at: DateTime::<Utc>::from_naive_utc_and_offset(m.updated_at, Utc),
        }
    }
}
