//! auth primitives: argon2id password hashing, random session tokens,
//! cookie name + lifetime constants. the route handlers and middleware
//! pull from here so security-relevant choices live in one place.

use std::time::Duration;

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum_extra::extract::cookie::{Cookie, SameSite};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use chrono::{Duration as ChronoDuration, Utc};
use rand::RngCore;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, DatabaseConnection, EntityTrait, QueryFilter,
};
use serde::Serialize;
use uuid::Uuid;

use crate::error::AppError;

pub const SESSION_COOKIE: &str = "sf_voice_session";
/// 30 days. matches the cookie max-age and the row's expires_at.
pub const SESSION_LIFETIME: Duration = Duration::from_secs(60 * 60 * 24 * 30);

/// 32 random bytes that identify a session. raw bytes go in the
/// sessions table PK; base64url goes in the cookie.
pub fn new_session_token() -> ([u8; 32], String) {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let encoded = URL_SAFE_NO_PAD.encode(bytes);
    (bytes, encoded)
}

/// decode a cookie value back into the 32-byte session id.
pub fn decode_session_cookie(value: &str) -> Option<[u8; 32]> {
    URL_SAFE_NO_PAD.decode(value).ok().and_then(|b| {
        if b.len() == 32 {
            let mut out = [0u8; 32];
            out.copy_from_slice(&b);
            Some(out)
        } else {
            None
        }
    })
}

/// argon2id password hash. parameters are the argon2 v0.5 defaults
/// (m=19 MiB, t=2, p=1) — OWASP-recommended for interactive auth.
pub fn hash_password(plain: &str) -> Result<String, AppError> {
    if plain.len() < 8 {
        return Err(AppError::BadRequest(
            "password must be at least 8 characters".into(),
        ));
    }
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(plain.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(format!("argon2 hash: {e}")))?;
    Ok(hash.to_string())
}

pub fn verify_password(plain: &str, hash: &str) -> bool {
    let parsed = match PasswordHash::new(hash) {
        Ok(p) => p,
        Err(_) => return false,
    };
    Argon2::default()
        .verify_password(plain.as_bytes(), &parsed)
        .is_ok()
}

/// shape the cookie consistently across login/signup/logout. secure
/// flag is OFF in dev so http://localhost works; turn on in prod via
/// COOKIE_SECURE=true.
pub fn build_session_cookie(value: String) -> Cookie<'static> {
    let secure = std::env::var("COOKIE_SECURE")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);
    Cookie::build((SESSION_COOKIE, value))
        .path("/")
        .http_only(true)
        .secure(secure)
        .same_site(SameSite::Lax)
        .max_age(time::Duration::seconds(SESSION_LIFETIME.as_secs() as i64))
        .build()
}

pub fn build_logout_cookie() -> Cookie<'static> {
    Cookie::build((SESSION_COOKIE, ""))
        .path("/")
        .http_only(true)
        .max_age(time::Duration::seconds(0))
        .build()
}

/// resolved auth context — attached to every authenticated request by
/// the middleware in routes/middleware.rs. handlers extract via the
/// FromRequestParts impl below.
#[derive(Debug, Clone, Serialize)]
pub struct AuthContext {
    pub user_id: Uuid,
    pub current_org_id: Uuid,
}

/// resolved admin context — same shape as AuthContext but only attached
/// when the user's email matches the sf-voice staff suffix. extracted
/// via FromRequestParts in middleware.rs. handlers that take this in
/// their signature get a compile-time guarantee that admin was verified.
#[derive(Debug, Clone, Serialize)]
pub struct AdminContext {
    pub user_id: Uuid,
    pub current_org_id: Uuid,
    pub email: String,
}

/// suffix that makes a user an internal sf-voice admin. hardcoded — the
/// rule is "anyone with an @sf-voice.sh email is staff", not a per-user
/// allowlist. duplicated in frontend Layout.tsx; if this ever changes,
/// update both.
pub const ADMIN_EMAIL_SUFFIX: &str = "@sf-voice.sh";

pub fn is_admin_email(email: &str) -> bool {
    email.to_ascii_lowercase().ends_with(ADMIN_EMAIL_SUFFIX)
}

/// loads a session row by token bytes + bumps last_used_at. returns
/// AuthContext on success. missing/expired sessions return Unauthorized.
pub async fn load_session(
    db: &DatabaseConnection,
    token: [u8; 32],
) -> Result<AuthContext, AppError> {
    let session = entities::sessions::Entity::find_by_id(token.to_vec())
        .one(db)
        .await?
        .ok_or(AppError::Unauthorized)?;

    if session.expires_at < Utc::now().naive_utc() {
        return Err(AppError::Unauthorized);
    }

    // best-effort bump of last_used_at. don't fail the request if this errors.
    let _ = entities::sessions::ActiveModel {
        id: Set(token.to_vec()),
        last_used_at: Set(Utc::now().naive_utc()),
        ..Default::default()
    }
    .update(db)
    .await;

    Ok(AuthContext {
        user_id: Uuid::from_slice(&session.user_id)
            .map_err(|e| AppError::Internal(e.to_string()))?,
        current_org_id: Uuid::from_slice(&session.current_org_id)
            .map_err(|e| AppError::Internal(e.to_string()))?,
    })
}

/// persist a fresh session. the caller sets the cookie with the base64
/// of `token_bytes`.
pub async fn create_session(
    db: &DatabaseConnection,
    user_id: Uuid,
    current_org_id: Uuid,
) -> Result<([u8; 32], String), AppError> {
    let (token_bytes, token_str) = new_session_token();
    let expires_at = Utc::now() + ChronoDuration::seconds(SESSION_LIFETIME.as_secs() as i64);

    entities::sessions::ActiveModel {
        id: Set(token_bytes.to_vec()),
        user_id: Set(user_id.as_bytes().to_vec()),
        current_org_id: Set(current_org_id.as_bytes().to_vec()),
        expires_at: Set(expires_at.naive_utc()),
        ..Default::default()
    }
    .insert(db)
    .await?;

    Ok((token_bytes, token_str))
}

pub async fn delete_session(db: &DatabaseConnection, token: [u8; 32]) -> Result<(), AppError> {
    entities::sessions::Entity::delete_by_id(token.to_vec())
        .exec(db)
        .await?;
    Ok(())
}

/// switch which org a session currently reads. used by the org-switcher
/// in phase I.
pub async fn switch_session_org(
    db: &DatabaseConnection,
    token: [u8; 32],
    new_org_id: Uuid,
) -> Result<(), AppError> {
    entities::sessions::ActiveModel {
        id: Set(token.to_vec()),
        current_org_id: Set(new_org_id.as_bytes().to_vec()),
        ..Default::default()
    }
    .update(db)
    .await?;
    Ok(())
}

/// look up an org_users membership row. returns the org_id of the
/// caller's first (oldest) membership, or NotFound if they have none.
/// used by login + create_org to pick a default current_org.
pub async fn first_org_for_user(db: &DatabaseConnection, user_id: Uuid) -> Result<Uuid, AppError> {
    use sea_orm::QueryOrder;
    let membership = entities::org_users::Entity::find()
        .filter(entities::org_users::Column::UserId.eq(user_id.as_bytes().to_vec()))
        .order_by_asc(entities::org_users::Column::CreatedAt)
        .one(db)
        .await?
        .ok_or_else(|| AppError::Internal("user has no org membership".into()))?;
    Uuid::from_slice(&membership.org_id).map_err(|e| AppError::Internal(e.to_string()))
}
