//! /api/org — read + update the resolved org's settings. org_id comes
//! from the authenticated session's `current_org_id`.

use axum::{extract::State, routing::get, Json, Router};
use sea_orm::{ActiveModelTrait, EntityTrait, IntoActiveModel, Set};
use serde::Deserialize;

use crate::{auth::AuthContext, error::AppError, models::Org, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new().route("/org", get(get_org).patch(update_org))
}

async fn get_org(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<Option<Org>>, AppError> {
    let row = entities::orgs::Entity::find_by_id(auth.current_org_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .map(Org::from);
    Ok(Json(row))
}

#[derive(Debug, Deserialize)]
pub struct UpdateOrgBody {
    pub config_repo_url: Option<String>,
    pub slack_webhook_url: Option<String>,
    pub bucket_name: Option<String>,
    pub bucket_prefix: Option<String>,
    pub bucket_region: Option<String>,
}

async fn update_org(
    State(state): State<AppState>,
    auth: AuthContext,
    Json(body): Json<UpdateOrgBody>,
) -> Result<Json<Option<Org>>, AppError> {
    // pattern replaces the SQL COALESCE: load the row, convert to
    // ActiveModel (every column unchanged), then mark only the fields
    // the caller actually sent. SeaORM emits an UPDATE that touches
    // just those columns.
    let model = entities::orgs::Entity::find_by_id(auth.current_org_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    let mut active = model.into_active_model();
    if let Some(v) = body.config_repo_url {
        active.config_repo_url = Set(Some(v));
    }
    if let Some(v) = body.slack_webhook_url {
        active.slack_webhook_url = Set(Some(v));
    }
    if let Some(v) = body.bucket_name {
        active.bucket_name = Set(Some(v));
    }
    if let Some(v) = body.bucket_prefix {
        active.bucket_prefix = Set(Some(v));
    }
    if let Some(v) = body.bucket_region {
        active.bucket_region = Set(Some(v));
    }
    active.update(&state.orm).await?;

    get_org(State(state), auth).await
}
