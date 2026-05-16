//! in-process broadcast registry for job step events. one
//! `broadcast::Sender` per `job_id`. sse handlers subscribe; job writers
//! publish.
//!
//! single-node assumption — when we scale to multiple api nodes we'll
//! switch to redis pub/sub or postgres listen/notify. documented in
//! core/backend/AGENTS.md → plan/runtime-conventions.md.

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Mutex;

use axum::response::sse::Event;
use sea_orm::EntityTrait;
use tokio::sync::broadcast;
use uuid::Uuid;

use crate::{
    error::AppError,
    models::{StepEvent, StepStatus},
    state::AppState,
};

/// channel capacity — old events are dropped when a subscriber lags
/// beyond this.
const CHANNEL_CAPACITY: usize = 64;

pub struct EventBroker {
    senders: Mutex<HashMap<Uuid, broadcast::Sender<StepEvent>>>,
}

impl EventBroker {
    pub fn new() -> Self {
        Self {
            senders: Mutex::new(HashMap::new()),
        }
    }

    /// subscribe to a job's event stream. creates the channel on first
    /// use so subscribers can connect before the publisher exists.
    pub fn subscribe(&self, job_id: Uuid) -> broadcast::Receiver<StepEvent> {
        let mut map = self.senders.lock().expect("EventBroker mutex poisoned");
        let tx = map
            .entry(job_id)
            .or_insert_with(|| broadcast::channel(CHANNEL_CAPACITY).0);
        tx.subscribe()
    }

    /// publish a step event. silently no-ops if there are no
    /// subscribers; the event is still persisted to jobs.progress_steps
    /// before this call, so a late subscriber's reconnect-replay covers
    /// the gap.
    pub fn publish(&self, job_id: Uuid, event: StepEvent) {
        let map = self.senders.lock().expect("EventBroker mutex poisoned");
        if let Some(tx) = map.get(&job_id) {
            let _ = tx.send(event);
        }
    }

    /// drop the channel for a finished job. callers don't have to call
    /// this — channels are cheap and bounded — but it tidies up.
    pub fn close(&self, job_id: Uuid) {
        let mut map = self.senders.lock().expect("EventBroker mutex poisoned");
        map.remove(&job_id);
    }
}

impl Default for EventBroker {
    fn default() -> Self {
        Self::new()
    }
}

/// replay the events already persisted on `jobs.progress_steps` so a
/// late subscriber catches everything that happened before they
/// connected. paired with `EventBroker::subscribe` for the live tail.
pub async fn load_existing_steps(
    state: &AppState,
    job_id: Uuid,
) -> Result<Vec<StepEvent>, AppError> {
    let job = entities::jobs::Entity::find_by_id(job_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?;
    let Some(job) = job else { return Ok(vec![]) };
    let Some(arr) = job.progress_steps else {
        return Ok(vec![]);
    };
    Ok(serde_json::from_value(arr).unwrap_or_default())
}

/// encode a StepEvent as an SSE `Event` with a typed name. clients
/// addEventListener on each name; data is the json-encoded StepEvent.
pub fn make_sse_event(ev: StepEvent) -> Result<Event, Infallible> {
    let name = match ev.status {
        StepStatus::Done => "step.done",
        StepStatus::Running => "step.running",
        StepStatus::Failed => "step.failed",
        StepStatus::Pending => "step.pending",
    };
    let data = serde_json::to_string(&ev).unwrap_or_default();
    Ok(Event::default().event(name).data(data))
}
