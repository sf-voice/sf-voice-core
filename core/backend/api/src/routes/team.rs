use axum::{
    extract::{Path, State},
    routing::{delete, get, post},
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64URL, Engine as _};
use chrono::{DateTime, Duration as ChronoDuration, Utc};
use rand::RngCore;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter, QueryOrder, SqlErr,
    TransactionTrait,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{auth::AuthContext, error::AppError, middleware::SessionToken, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/org/members", get(list_members))
        .route("/org/invites", get(list_invites).post(create_invite))
        .route("/org/invites/:id", delete(revoke_invite))
        .route("/invites/:token", get(preview_invite))
        .route("/invites/:token/accept", post(accept_invite))
}

#[derive(Debug, Serialize)]
pub struct MemberDto {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: Option<String>,
    pub role: String,
    pub joined_at: DateTime<Utc>,
}

async fn list_members(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<Vec<MemberDto>>, AppError> {
    // memberships first (small, ordered), then a single users-by-id batch.
    let memberships = entities::org_users::Entity::find()
        .filter(entities::org_users::Column::OrgId.eq(auth.current_org_id.as_bytes().to_vec()))
        .order_by_asc(entities::org_users::Column::CreatedAt)
        .all(&state.orm)
        .await?;

    let user_ids: Vec<Vec<u8>> = memberships.iter().map(|m| m.user_id.clone()).collect();
    let users = entities::users::Entity::find()
        .filter(entities::users::Column::Id.is_in(user_ids))
        .all(&state.orm)
        .await?;
    let users_by_id: std::collections::HashMap<Vec<u8>, entities::users::Model> =
        users.into_iter().map(|u| (u.id.clone(), u)).collect();

    let members = memberships
        .into_iter()
        .filter_map(|m| {
            users_by_id.get(&m.user_id).map(|u| MemberDto {
                user_id: Uuid::from_slice(&u.id).expect("users.id is BINARY(16)"),
                email: u.email.clone(),
                display_name: u.display_name.clone(),
                role: m.role,
                joined_at: DateTime::<Utc>::from_naive_utc_and_offset(m.created_at, Utc),
            })
        })
        .collect();

    Ok(Json(members))
}

#[derive(Debug, Serialize)]
pub struct InviteDto {
    pub id: Uuid,
    pub email: String,
    pub role: String,
    pub token: String,
    pub accept_url: String,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub accepted_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateInviteBody {
    pub email: String,
    pub role: Option<String>, // 'owner' | 'member', defaults to 'member'
}

async fn create_invite(
    State(state): State<AppState>,
    auth: AuthContext,
    Json(body): Json<CreateInviteBody>,
) -> Result<Json<InviteDto>, AppError> {
    let email = body.email.trim().to_lowercase();
    if !email.contains('@') {
        return Err(AppError::BadRequest("invalid email".into()));
    }
    let role = body.role.as_deref().unwrap_or("member");
    if role != "owner" && role != "member" {
        return Err(AppError::BadRequest("role must be owner or member".into()));
    }

    let id = Uuid::now_v7();
    let token = generate_invite_token();
    let expires_at = Utc::now() + ChronoDuration::days(7);

    entities::invites::ActiveModel {
        id: Set(id.as_bytes().to_vec()),
        org_id: Set(auth.current_org_id.as_bytes().to_vec()),
        email: Set(email.clone()),
        role: Set(role.to_string()),
        token: Set(token.clone()),
        invited_by: Set(auth.user_id.as_bytes().to_vec()),
        expires_at: Set(expires_at.naive_utc()),
        ..Default::default()
    }
    .insert(&state.orm)
    .await?;

    Ok(Json(InviteDto {
        id,
        email,
        role: role.to_string(),
        accept_url: accept_url(&token),
        token,
        created_at: Utc::now(),
        expires_at,
        accepted_at: None,
    }))
}

async fn list_invites(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<Vec<InviteDto>>, AppError> {
    let invites = entities::invites::Entity::find()
        .filter(entities::invites::Column::OrgId.eq(auth.current_org_id.as_bytes().to_vec()))
        .order_by_desc(entities::invites::Column::CreatedAt)
        .all(&state.orm)
        .await?;

    let out = invites
        .into_iter()
        .map(|i| InviteDto {
            id: Uuid::from_slice(&i.id).expect("invites.id is BINARY(16)"),
            email: i.email,
            role: i.role,
            accept_url: accept_url(&i.token),
            token: i.token,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(i.created_at, Utc),
            expires_at: DateTime::<Utc>::from_naive_utc_and_offset(i.expires_at, Utc),
            accepted_at: i
                .accepted_at
                .map(|t| DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
        })
        .collect();

    Ok(Json(out))
}

async fn revoke_invite(
    State(state): State<AppState>,
    auth: AuthContext,
    Path(id): Path<Uuid>,
) -> Result<axum::http::StatusCode, AppError> {
    let res = entities::invites::Entity::delete_many()
        .filter(entities::invites::Column::Id.eq(id.as_bytes().to_vec()))
        .filter(entities::invites::Column::OrgId.eq(auth.current_org_id.as_bytes().to_vec()))
        .filter(entities::invites::Column::AcceptedAt.is_null())
        .exec(&state.orm)
        .await?;
    if res.rows_affected == 0 {
        return Err(AppError::NotFound);
    }
    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize)]
pub struct InvitePreview {
    pub org_name: String,
    pub org_slug: String,
    pub email: String,
    pub role: String,
    pub expires_at: DateTime<Utc>,
    pub already_accepted: bool,
    pub expired: bool,
}

async fn preview_invite(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> Result<Json<InvitePreview>, AppError> {
    let invite = entities::invites::Entity::find()
        .filter(entities::invites::Column::Token.eq(token))
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    let org = entities::orgs::Entity::find_by_id(invite.org_id.clone())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;

    let expires_at = DateTime::<Utc>::from_naive_utc_and_offset(invite.expires_at, Utc);
    Ok(Json(InvitePreview {
        org_name: org.name,
        org_slug: org.slug,
        email: invite.email,
        role: invite.role,
        expires_at,
        already_accepted: invite.accepted_at.is_some(),
        expired: expires_at < Utc::now(),
    }))
}

#[derive(Debug, Serialize)]
pub struct AcceptResponse {
    pub org_id: Uuid,
    pub org_name: String,
    pub org_slug: String,
}

async fn accept_invite(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(session_token): SessionToken,
    Path(token): Path<String>,
) -> Result<Json<AcceptResponse>, AppError> {
    let invite = entities::invites::Entity::find()
        .filter(entities::invites::Column::Token.eq(token.clone()))
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;

    if invite.accepted_at.is_some() {
        return Err(AppError::Conflict("invite already accepted".into()));
    }
    let expires_at = DateTime::<Utc>::from_naive_utc_and_offset(invite.expires_at, Utc);
    if expires_at < Utc::now() {
        return Err(AppError::BadRequest("invite expired".into()));
    }

    // verify the logged-in user's email matches the invite's.
    let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;
    if user.email.to_lowercase() != invite.email.to_lowercase() {
        return Err(AppError::BadRequest(format!(
            "invite is for {}, you're signed in as {}",
            invite.email, user.email
        )));
    }

    let org = entities::orgs::Entity::find_by_id(invite.org_id.clone())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    let org_id = Uuid::from_slice(&invite.org_id).map_err(|e| AppError::Internal(e.to_string()))?;

    let txn = state.orm.begin().await?;

    // idempotent membership row — if they're already in the org for any
    // reason, don't create a duplicate. catch the UNIQUE error softly.
    let ou_id = Uuid::now_v7();
    let res = entities::org_users::ActiveModel {
        id: Set(ou_id.as_bytes().to_vec()),
        org_id: Set(invite.org_id.clone()),
        user_id: Set(auth.user_id.as_bytes().to_vec()),
        role: Set(invite.role.clone()),
        ..Default::default()
    }
    .insert(&txn)
    .await;
    if let Err(e) = res {
        if !matches!(e.sql_err(), Some(SqlErr::UniqueConstraintViolation(_))) {
            return Err(e.into());
        }
        // already a member — fall through to update accepted_at + switch session
    }

    entities::invites::ActiveModel {
        id: Set(invite.id),
        accepted_at: Set(Some(Utc::now().naive_utc())),
        ..Default::default()
    }
    .update(&txn)
    .await?;

    // switch the session's current org to the freshly-joined one.
    entities::sessions::ActiveModel {
        id: Set(session_token.to_vec()),
        current_org_id: Set(invite.org_id),
        ..Default::default()
    }
    .update(&txn)
    .await?;

    txn.commit().await?;

    Ok(Json(AcceptResponse {
        org_id,
        org_name: org.name,
        org_slug: org.slug,
    }))
}

fn generate_invite_token() -> String {
    let mut bytes = [0u8; 24];
    rand::thread_rng().fill_bytes(&mut bytes);
    B64URL.encode(bytes)
}

fn accept_url(token: &str) -> String {
    let base =
        std::env::var("SF_VOICE_APP_URL").unwrap_or_else(|_| "http://localhost:3000".to_string());
    format!("{base}/accept-invite/{token}")
}
