//! /api/slices — read a single prompt_slice. creation lives under
//! /api/calls/:id/slices in calls.rs.

use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use uuid::Uuid;

use crate::{error::AppError, models::PromptSlice, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new().route("/slices/:id", get(get_slice))
}

async fn get_slice(
    State(state): State<AppState>,
    auth: crate::auth::AuthContext,
    Path(id): Path<Uuid>,
) -> Result<Json<Option<PromptSlice>>, AppError> {
    let row = entities::prompt_slices::Entity::find_by_id(id.as_bytes().to_vec())
        .filter(entities::prompt_slices::Column::OrgId.eq(auth.current_org_id.as_bytes().to_vec()))
        .one(&state.orm)
        .await?
        .map(PromptSlice::from);
    Ok(Json(row))
}
