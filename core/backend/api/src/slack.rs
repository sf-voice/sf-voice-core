use reqwest::Client;
use serde_json::json;

use crate::models::{StepEvent, StepStatus};

const STATUS_EMOJI_DONE: &str = ":white_check_mark:";
const STATUS_EMOJI_RUNNING: &str = ":hourglass_flowing_sand:";
const STATUS_EMOJI_FAILED: &str = ":x:";
const STATUS_EMOJI_PENDING: &str = ":hourglass:";

pub async fn post_step(client: &Client, webhook_url: &str, job_id: &str, event: &StepEvent) {
    let emoji = match event.status {
        StepStatus::Done => STATUS_EMOJI_DONE,
        StepStatus::Running => STATUS_EMOJI_RUNNING,
        StepStatus::Failed => STATUS_EMOJI_FAILED,
        StepStatus::Pending => STATUS_EMOJI_PENDING,
    };
    let text = match &event.detail {
        Some(d) => format!("`{}` {} *{}* — {}", job_id, emoji, event.step, d),
        None => format!("`{}` {} *{}*", job_id, emoji, event.step),
    };

    let body = json!({ "text": text });
    match client
        .post(webhook_url)
        .json(&body)
        .send()
        .await
        .and_then(|r| r.error_for_status())
    {
        Ok(_) => {}
        Err(e) => tracing::warn!(?e, %job_id, "slack webhook post failed"),
    }
}
