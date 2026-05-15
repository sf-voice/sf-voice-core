use axum::{
    extract::{Path, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter, QueryOrder, SqlErr,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    auth::{hash_password, verify_password, AuthContext},
    error::AppError,
    middleware::SessionToken,
    routes::auth::UserDto,
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/profile", patch(update_profile))
        .route("/me/password", post(change_password))
        .route("/me/email", post(change_email))
        .route("/me/sessions", get(list_sessions))
        .route("/me/sessions/:id", delete(revoke_session))
}

#[derive(Debug, Deserialize)]
pub struct UpdateProfileBody {
    pub display_name: Option<String>,
}

async fn update_profile(
    State(state): State<AppState>,
    auth: AuthContext,
    Json(body): Json<UpdateProfileBody>,
) -> Result<Json<UserDto>, AppError> {
    // empty string → NULL; treating "" identically to null avoids storing
    // a meaningless empty display name.
    let display_name = body.display_name.and_then(|s| {
        let t = s.trim().to_string();
        if t.is_empty() {
            None
        } else {
            Some(t)
        }
    });

    entities::users::ActiveModel {
        id: Set(auth.user_id.as_bytes().to_vec()),
        display_name: Set(display_name),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;

    fetch_user(&state, auth.user_id).await.map(Json)
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordBody {
    pub current_password: String,
    pub new_password: String,
}

async fn change_password(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(current_token): SessionToken,
    Json(body): Json<ChangePasswordBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let current_hash = user.password_hash.ok_or(AppError::Unauthorized)?;

    if !verify_password(&body.current_password, &current_hash) {
        return Err(AppError::BadRequest("current password is wrong".into()));
    }

    let new_hash = hash_password(&body.new_password)?;
    entities::users::ActiveModel {
        id: Set(auth.user_id.as_bytes().to_vec()),
        password_hash: Set(Some(new_hash)),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;

    invalidate_other_sessions(&state, auth.user_id, current_token).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

#[derive(Debug, Deserialize)]
pub struct ChangeEmailBody {
    pub new_email: String,
    pub current_password: String,
}

async fn change_email(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(current_token): SessionToken,
    Json(body): Json<ChangeEmailBody>,
) -> Result<Json<UserDto>, AppError> {
    let new_email = body.new_email.trim().to_ascii_lowercase();
    // very mild validation — real verification is in the deferred email
    // confirmation flow (see core/TODO.md → "User settings backend").
    if !new_email.contains('@') || new_email.len() < 3 {
        return Err(AppError::BadRequest("new_email looks invalid".into()));
    }

    let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let current_hash = user.password_hash.ok_or(AppError::Unauthorized)?;
    if !verify_password(&body.current_password, &current_hash) {
        return Err(AppError::BadRequest("current password is wrong".into()));
    }

    let res = entities::users::ActiveModel {
        id: Set(auth.user_id.as_bytes().to_vec()),
        email: Set(new_email),
        ..Default::default()
    }
    .update(&state.orm)
    .await;
    if let Err(e) = res {
        if matches!(e.sql_err(), Some(SqlErr::UniqueConstraintViolation(_))) {
            return Err(AppError::Conflict(
                "an account with that email already exists".into(),
            ));
        }
        return Err(e.into());
    }

    invalidate_other_sessions(&state, auth.user_id, current_token).await?;
    fetch_user(&state, auth.user_id).await.map(Json)
}

#[derive(Debug, Serialize)]
pub struct SessionDto {
    pub id: String,
    pub ip: Option<String>,
    pub user_agent: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub is_current: bool,
}

async fn list_sessions(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(current_token): SessionToken,
) -> Result<Json<Vec<SessionDto>>, AppError> {
    let now = Utc::now().naive_utc();
    let sessions = entities::sessions::Entity::find()
        .filter(entities::sessions::Column::UserId.eq(auth.user_id.as_bytes().to_vec()))
        .filter(entities::sessions::Column::ExpiresAt.gt(now))
        .order_by_desc(entities::sessions::Column::LastUsedAt)
        .all(&state.orm)
        .await?;

    let out = sessions
        .into_iter()
        .map(|s| SessionDto {
            is_current: s.id == current_token,
            id: hex_encode(&s.id),
            ip: s.ip,
            user_agent: s.user_agent,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(s.created_at, Utc),
            last_used_at: Some(DateTime::<Utc>::from_naive_utc_and_offset(
                s.last_used_at,
                Utc,
            )),
        })
        .collect();

    Ok(Json(out))
}

async fn revoke_session(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(current_token): SessionToken,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let target = hex_decode(&id)
        .ok_or_else(|| AppError::BadRequest("session id must be 64 hex chars".into()))?;

    if target == current_token {
        return Err(AppError::BadRequest(
            "cannot revoke the current session — use sign out".into(),
        ));
    }

    let res = entities::sessions::Entity::delete_many()
        .filter(entities::sessions::Column::Id.eq(target.to_vec()))
        .filter(entities::sessions::Column::UserId.eq(auth.user_id.as_bytes().to_vec()))
        .exec(&state.orm)
        .await?;
    if res.rows_affected == 0 {
        return Err(AppError::NotFound);
    }
    Ok(Json(serde_json::json!({ "ok": true })))
}

async fn fetch_user(state: &AppState, user_id: Uuid) -> Result<UserDto, AppError> {
    let user = entities::users::Entity::find_by_id(user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(UserDto {
        id: user_id,
        email: user.email,
        display_name: user.display_name,
        created_at: DateTime::<Utc>::from_naive_utc_and_offset(user.created_at, Utc),
    })
}

async fn invalidate_other_sessions(
    state: &AppState,
    user_id: Uuid,
    keep_token: [u8; 32],
) -> Result<(), AppError> {
    entities::sessions::Entity::delete_many()
        .filter(entities::sessions::Column::UserId.eq(user_id.as_bytes().to_vec()))
        .filter(entities::sessions::Column::Id.ne(keep_token.to_vec()))
        .exec(&state.orm)
        .await?;
    Ok(())
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(&mut s, "{b:02x}");
    }
    s
}

fn hex_decode(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}
