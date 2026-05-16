//! /api/admin/* — staff console endpoints. every handler takes
//! AdminContext, so the @sf-voice.sh email gate is enforced at the
//! extractor level (see middleware.rs). non-staff requests get 403.
//!
//! aggregations here cross orgs by design — that's the whole point of
//! the admin surface.

use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use chrono::{DateTime, Utc};
use sea_orm::{
    ColumnTrait, Condition, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{auth::AdminContext, error::AppError, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/admin/orgs", get(list_orgs))
        .route("/admin/jobs", get(list_jobs))
}

// ─────────────────────────────────────────────────────────────────────
// GET /api/admin/orgs
// every org with rolled-up stats. small N (low tens of orgs at v1
// scale), so per-row aggregate queries are fine. revisit when N >
// a few hundred.
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct AdminOrgRow {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub member_count: i64,
    pub bucket_method: Option<String>,
    pub bucket_verified_at: Option<DateTime<Utc>>,
    pub last_call_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

async fn list_orgs(
    State(state): State<AppState>,
    _admin: AdminContext,
) -> Result<Json<Vec<AdminOrgRow>>, AppError> {
    let orgs = entities::orgs::Entity::find()
        .order_by_desc(entities::orgs::Column::CreatedAt)
        .all(&state.orm)
        .await?;

    let mut out = Vec::with_capacity(orgs.len());
    for o in orgs {
        // member count
        let member_count = entities::org_users::Entity::find()
            .filter(entities::org_users::Column::OrgId.eq(o.id.clone()))
            .count(&state.orm)
            .await? as i64;

        // last call timestamp — fetch the most recent call's started_at.
        let last_call = entities::calls::Entity::find()
            .filter(entities::calls::Column::OrgId.eq(o.id.clone()))
            .order_by_desc(entities::calls::Column::StartedAt)
            .one(&state.orm)
            .await?
            .map(|c| DateTime::<Utc>::from_naive_utc_and_offset(c.started_at, Utc));

        out.push(AdminOrgRow {
            id: Uuid::from_slice(&o.id).expect("orgs.id is BINARY(16)"),
            name: o.name,
            slug: o.slug,
            member_count,
            bucket_method: o.bucket_auth_method,
            bucket_verified_at: o
                .bucket_verified_at
                .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
            last_call_at: last_call,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(o.created_at, Utc),
        });
    }

    Ok(Json(out))
}

// ─────────────────────────────────────────────────────────────────────
// GET /api/admin/jobs?status=&kind=&org_id=&limit=
// recent jobs across all orgs. filters are all optional; sane default
// orders newest-first and caps to 100.
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ListJobsQuery {
    pub status: Option<String>,
    pub kind: Option<String>,
    pub org_id: Option<Uuid>,
    pub limit: Option<u32>,
}

#[derive(Debug, Serialize)]
pub struct AdminJobRow {
    pub id: Uuid,
    pub org_id: Uuid,
    pub kind: String,
    pub status: String,
    pub subject_type: Option<String>,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub finished_at: Option<DateTime<Utc>>,
}

async fn list_jobs(
    State(state): State<AppState>,
    _admin: AdminContext,
    Query(q): Query<ListJobsQuery>,
) -> Result<Json<Vec<AdminJobRow>>, AppError> {
    // bounded so a bad caller can't blow up the response. 100 is plenty
    // for the staff UI's table view; the page asks for more on demand.
    let limit = q.limit.unwrap_or(50).min(500) as u64;

    let mut cond = Condition::all();
    if let Some(s) = q.status {
        cond = cond.add(entities::jobs::Column::Status.eq(s));
    }
    if let Some(k) = q.kind {
        cond = cond.add(entities::jobs::Column::Kind.eq(k));
    }
    if let Some(o) = q.org_id {
        cond = cond.add(entities::jobs::Column::OrgId.eq(o.as_bytes().to_vec()));
    }

    let jobs = entities::jobs::Entity::find()
        .filter(cond)
        .order_by_desc(entities::jobs::Column::CreatedAt)
        .limit(limit)
        .all(&state.orm)
        .await?;

    let out = jobs
        .into_iter()
        .map(|j| AdminJobRow {
            id: Uuid::from_slice(&j.id).expect("jobs.id is BINARY(16)"),
            org_id: Uuid::from_slice(&j.org_id).expect("jobs.org_id is BINARY(16)"),
            kind: j.kind,
            status: j.status,
            subject_type: Some(j.subject_type),
            error_message: j.error_message,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(j.created_at, Utc),
            started_at: j
                .started_at
                .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
            finished_at: j
                .finished_at
                .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
        })
        .collect();

    Ok(Json(out))
}
