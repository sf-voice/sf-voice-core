use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,

    #[error("unauthorized")]
    Unauthorized,

    #[error("forbidden")]
    Forbidden,

    #[error("conflict: {0}")]
    Conflict(String),

    #[error("bad request: {0}")]
    BadRequest(String),

    #[error("orm error: {0}")]
    Orm(#[from] sea_orm::DbErr),

    #[error("http error: {0}")]
    Reqwest(#[from] reqwest::Error),

    // duckdb is still wired for /api/db/ping; keep the variant so the
    // existing handler doesn't have to change shape.
    #[error("duckdb error: {0}")]
    Duckdb(#[from] duckdb::Error),

    #[error("lock poisoned")]
    Poisoned,

    #[error("internal: {0}")]
    Internal(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::NotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::Forbidden => (StatusCode::FORBIDDEN, self.to_string()),
            AppError::Conflict(_) => (StatusCode::CONFLICT, self.to_string()),
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::Orm(sea_orm::DbErr::RecordNotFound(_)) => {
                (StatusCode::NOT_FOUND, "not found".into())
            }
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        if status.is_server_error() {
            tracing::error!("api error: {self}");
        } else {
            tracing::warn!("api error: {self}");
        }

        (status, Json(json!({ "error": message }))).into_response()
    }
}
