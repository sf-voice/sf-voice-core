//! /api/org/members, /api/org/invites, /api/invites/:token — team mgmt.

use axum::{
    extract::{Path, State},
    routing::{delete, get, post},
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64URL, Engine as _};
use chrono::{DateTime, Duration as ChronoDuration, Utc};
use rand::RngCore;
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
    let rows: Vec<(Vec<u8>, String, Option<String>, String, DateTime<Utc>)> = sqlx::query_as(
        r#"
        SELECT u.id, u.email, u.display_name, ou.role, ou.created_at
        FROM org_users ou
        JOIN users u ON u.id = ou.user_id
        WHERE ou.org_id = ?
        ORDER BY ou.created_at ASC
        "#,
    )
    .bind(auth.current_org_id.as_bytes().as_slice())
    .fetch_all(&state.pool)
    .await?;

    let members = rows
        .into_iter()
        .map(|(uid, email, name, role, joined)| {
            Ok(MemberDto {
                user_id: Uuid::from_slice(&uid).map_err(|e| AppError::Internal(e.to_string()))?,
                email,
                display_name: name,
                role,
                joined_at: joined,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

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

    sqlx::query(
        r#"
        INSERT INTO invites
            (id, org_id, email, role, token, invited_by, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        "#,
    )
    .bind(id.as_bytes().as_slice())
    .bind(auth.current_org_id.as_bytes().as_slice())
    .bind(&email)
    .bind(role)
    .bind(&token)
    .bind(auth.user_id.as_bytes().as_slice())
    .bind(expires_at)
    .execute(&state.pool)
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
    let rows: Vec<(
        Vec<u8>,
        String,
        String,
        String,
        DateTime<Utc>,
        DateTime<Utc>,
        Option<DateTime<Utc>>,
    )> = sqlx::query_as(
        r#"
        SELECT id, email, role, token, created_at, expires_at, accepted_at
        FROM invites
        WHERE org_id = ?
        ORDER BY created_at DESC
        "#,
    )
    .bind(auth.current_org_id.as_bytes().as_slice())
    .fetch_all(&state.pool)
    .await?;

    let invites = rows
        .into_iter()
        .map(|(id, email, role, token, created, expires, accepted)| {
            Ok(InviteDto {
                id: Uuid::from_slice(&id).map_err(|e| AppError::Internal(e.to_string()))?,
                email,
                role,
                accept_url: accept_url(&token),
                token,
                created_at: created,
                expires_at: expires,
                accepted_at: accepted,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(invites))
}

async fn revoke_invite(
    State(state): State<AppState>,
    auth: AuthContext,
    Path(id): Path<Uuid>,
) -> Result<axum::http::StatusCode, AppError> {
    let res =
        sqlx::query("DELETE FROM invites WHERE id = ? AND org_id = ? AND accepted_at IS NULL")
            .bind(id.as_bytes().as_slice())
            .bind(auth.current_org_id.as_bytes().as_slice())
            .execute(&state.pool)
            .await?;
    if res.rows_affected() == 0 {
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
    let row: Option<(
        String,
        String,
        String,
        String,
        DateTime<Utc>,
        Option<DateTime<Utc>>,
    )> = sqlx::query_as(
        r#"
            SELECT o.name, o.slug, i.email, i.role, i.expires_at, i.accepted_at
            FROM invites i
            JOIN orgs o ON o.id = i.org_id
            WHERE i.token = ?
            "#,
    )
    .bind(&token)
    .fetch_optional(&state.pool)
    .await?;

    let (org_name, org_slug, email, role, expires_at, accepted_at) =
        row.ok_or(AppError::NotFound)?;

    Ok(Json(InvitePreview {
        org_name,
        org_slug,
        email,
        role,
        expires_at,
        already_accepted: accepted_at.is_some(),
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
    // load invite + the inviting org's name in one shot.
    let row: Option<(
        Vec<u8>,
        String,
        String,
        String,
        DateTime<Utc>,
        Option<DateTime<Utc>>,
        String,
        String,
    )> = sqlx::query_as(
        r#"
            SELECT i.org_id, i.email, i.role, i.token, i.expires_at, i.accepted_at,
                   o.name, o.slug
            FROM invites i
            JOIN orgs o ON o.id = i.org_id
            WHERE i.token = ?
            "#,
    )
    .bind(&token)
    .fetch_optional(&state.pool)
    .await?;

    let (org_id_bytes, invite_email, role, _token, expires_at, accepted_at, org_name, org_slug) =
        row.ok_or(AppError::NotFound)?;

    if accepted_at.is_some() {
        return Err(AppError::Conflict("invite already accepted".into()));
    }
    if expires_at < Utc::now() {
        return Err(AppError::BadRequest("invite expired".into()));
    }

    // verify the logged-in user's email matches the invite's.
    let user_email: (String,) = sqlx::query_as("SELECT email FROM users WHERE id = ?")
        .bind(auth.user_id.as_bytes().as_slice())
        .fetch_one(&state.pool)
        .await?;
    if user_email.0.to_lowercase() != invite_email.to_lowercase() {
        return Err(AppError::BadRequest(format!(
            "invite is for {invite_email}, you're signed in as {}",
            user_email.0
        )));
    }

    let org_id = Uuid::from_slice(&org_id_bytes).map_err(|e| AppError::Internal(e.to_string()))?;

    let mut tx = state.pool.begin().await?;

    // idempotent membership row — if they're already in the org for any
    // reason, don't create a duplicate. catch the UNIQUE error softly.
    let ou_id = Uuid::now_v7();
    match sqlx::query("INSERT INTO org_users (id, org_id, user_id, role) VALUES (?, ?, ?, ?)")
        .bind(ou_id.as_bytes().as_slice())
        .bind(&org_id_bytes)
        .bind(auth.user_id.as_bytes().as_slice())
        .bind(&role)
        .execute(&mut *tx)
        .await
    {
        Ok(_) => {}
        // already a member of this org — invite is still valid, just a
        // no-op on the membership side. carries through to accepted_at.
        Err(sqlx::Error::Database(db_err)) if db_err.is_unique_violation() => {}
        Err(e) => return Err(AppError::from(e)),
    }

    sqlx::query("UPDATE invites SET accepted_at = CURRENT_TIMESTAMP WHERE token = ?")
        .bind(&token)
        .execute(&mut *tx)
        .await?;

    // switch the session's current org to the freshly-joined one.
    sqlx::query("UPDATE sessions SET current_org_id = ? WHERE id = ?")
        .bind(&org_id_bytes)
        .bind(&session_token[..])
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;

    Ok(Json(AcceptResponse {
        org_id,
        org_name,
        org_slug,
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
