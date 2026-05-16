//! /api/auth/* — signup, login, logout. these are the only routes that
//! do NOT require an existing session (signup creates one; login creates
//! one; logout drops one).
//!
//! /api/me lives here too — it's the canonical "am i logged in" probe,
//! requires AuthContext, returns the user + current org.

use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use axum_extra::extract::cookie::CookieJar;
use chrono::{DateTime, Utc};
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, ConnectionTrait, EntityTrait, QueryFilter,
    QueryOrder, SqlErr, TransactionTrait,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    auth::{
        build_logout_cookie, build_session_cookie, create_session, delete_session,
        first_org_for_user, hash_password, switch_session_org, verify_password, AuthContext,
    },
    error::AppError,
    middleware::SessionToken,
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/signup", post(signup))
        .route("/auth/login", post(login))
        .route("/auth/logout", post(logout))
        .route("/me", get(me))
        .route("/me/orgs", get(list_my_orgs))
        .route("/me/switch-org", post(switch_org))
        .route("/orgs", post(create_org))
}

// ─────────────────────────────────────────────────────────────────────
// signup
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct SignupBody {
    pub email: String,
    pub password: String,
    pub org_name: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct AuthedResponse {
    pub user: UserDto,
    pub org: OrgDto,
}

#[derive(Debug, Serialize)]
pub struct UserDto {
    pub id: Uuid,
    pub email: String,
    pub display_name: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct OrgDto {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
}

async fn signup(
    State(state): State<AppState>,
    jar: CookieJar,
    Json(body): Json<SignupBody>,
) -> Result<(CookieJar, Json<AuthedResponse>), AppError> {
    let email = body.email.trim().to_lowercase();
    if !email.contains('@') || email.len() > 254 {
        return Err(AppError::BadRequest("invalid email".into()));
    }
    let password_hash = hash_password(&body.password)?;

    let user_id = Uuid::now_v7();
    let org_id = Uuid::now_v7();
    let org_user_id = Uuid::now_v7();

    let org_name = body
        .org_name
        .as_ref()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            // derive from email local part. "j.smith@acme.com" → "Acme".
            email
                .split('@')
                .nth(1)
                .and_then(|d| d.split('.').next())
                .map(|s| {
                    let mut c = s.chars();
                    match c.next() {
                        Some(first) => first.to_uppercase().collect::<String>() + c.as_str(),
                        None => "Workspace".into(),
                    }
                })
                .unwrap_or_else(|| "Workspace".into())
        });
    let slug = make_slug(&org_name);

    let txn = state.orm.begin().await?;

    // unique email guard. plain SELECT before INSERT is racy in principle;
    // the UNIQUE index will catch it and we translate to Conflict.
    let user_active = entities::users::ActiveModel {
        id: Set(user_id.as_bytes().to_vec()),
        email: Set(email.clone()),
        password_hash: Set(Some(password_hash)),
        ..Default::default()
    };
    if let Err(e) = user_active.insert(&txn).await {
        if matches!(e.sql_err(), Some(SqlErr::UniqueConstraintViolation(_))) {
            return Err(AppError::Conflict("email already registered".into()));
        }
        return Err(e.into());
    }

    entities::orgs::ActiveModel {
        id: Set(org_id.as_bytes().to_vec()),
        name: Set(org_name.clone()),
        slug: Set(slug.clone()),
        ..Default::default()
    }
    .insert(&txn)
    .await?;

    entities::org_users::ActiveModel {
        id: Set(org_user_id.as_bytes().to_vec()),
        org_id: Set(org_id.as_bytes().to_vec()),
        user_id: Set(user_id.as_bytes().to_vec()),
        role: Set("owner".into()),
        ..Default::default()
    }
    .insert(&txn)
    .await?;

    txn.commit().await?;

    let (_, token_str) = create_session(&state.orm, user_id, org_id).await?;
    let jar = jar.add(build_session_cookie(token_str));

    Ok((
        jar,
        Json(AuthedResponse {
            user: UserDto {
                id: user_id,
                email,
                display_name: None,
                created_at: Utc::now(),
            },
            org: OrgDto {
                id: org_id,
                name: org_name,
                slug,
            },
        }),
    ))
}

// ─────────────────────────────────────────────────────────────────────
// login
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct LoginBody {
    pub email: String,
    pub password: String,
}

async fn login(
    State(state): State<AppState>,
    jar: CookieJar,
    Json(body): Json<LoginBody>,
) -> Result<(CookieJar, Json<AuthedResponse>), AppError> {
    let email = body.email.trim().to_lowercase();

    let user = entities::users::Entity::find()
        .filter(entities::users::Column::Email.eq(email.clone()))
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;

    let hash = user.password_hash.as_ref().ok_or(AppError::Unauthorized)?; // oauth-only user
    if !verify_password(&body.password, hash) {
        return Err(AppError::Unauthorized);
    }
    let user_id =
        Uuid::from_slice(&user.id).map_err(|e| AppError::Internal(e.to_string()))?;

    // pick the first org this user belongs to as the current org. org
    // switcher (phase I) lets them change later.
    let org_id = first_org_for_user(&state.orm, user_id).await?;

    let (_, token_str) = create_session(&state.orm, user_id, org_id).await?;
    let jar = jar.add(build_session_cookie(token_str));

    let resp = hydrate_authed(&state.orm, user_id, org_id, email).await?;
    Ok((jar, Json(resp)))
}

// ─────────────────────────────────────────────────────────────────────
// logout
// ─────────────────────────────────────────────────────────────────────

async fn logout(
    State(state): State<AppState>,
    jar: CookieJar,
    token: Option<axum::extract::Extension<SessionToken>>,
) -> Result<CookieJar, AppError> {
    if let Some(axum::extract::Extension(SessionToken(bytes))) = token {
        delete_session(&state.orm, bytes).await?;
    }
    Ok(jar.add(build_logout_cookie()))
}

// ─────────────────────────────────────────────────────────────────────
// me
// ─────────────────────────────────────────────────────────────────────

async fn me(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<AuthedResponse>, AppError> {
    let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let resp =
        hydrate_authed(&state.orm, auth.user_id, auth.current_org_id, user.email).await?;
    Ok(Json(resp))
}

// ─────────────────────────────────────────────────────────────────────
// helpers
// ─────────────────────────────────────────────────────────────────────

async fn hydrate_authed<C: ConnectionTrait>(
    db: &C,
    user_id: Uuid,
    org_id: Uuid,
    email: String,
) -> Result<AuthedResponse, AppError> {
    let user = entities::users::Entity::find_by_id(user_id.as_bytes().to_vec())
        .one(db)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let org = entities::orgs::Entity::find_by_id(org_id.as_bytes().to_vec())
        .one(db)
        .await?
        .ok_or(AppError::NotFound)?;

    Ok(AuthedResponse {
        user: UserDto {
            id: user_id,
            email,
            display_name: user.display_name,
            created_at: DateTime::<Utc>::from_naive_utc_and_offset(user.created_at, Utc),
        },
        org: OrgDto {
            id: org_id,
            name: org.name,
            slug: org.slug,
        },
    })
}

// ─────────────────────────────────────────────────────────────────────
// GET /api/me/orgs  — list every org this user belongs to
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct OrgMembershipDto {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub role: String,
    pub is_current: bool,
}

async fn list_my_orgs(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<Vec<OrgMembershipDto>>, AppError> {
    // load memberships for this user, oldest first.
    let memberships = entities::org_users::Entity::find()
        .filter(entities::org_users::Column::UserId.eq(auth.user_id.as_bytes().to_vec()))
        .order_by_asc(entities::org_users::Column::CreatedAt)
        .all(&state.orm)
        .await?;

    // load the matching orgs in one query, then index for the join.
    let org_ids: Vec<Vec<u8>> = memberships.iter().map(|m| m.org_id.clone()).collect();
    let orgs = entities::orgs::Entity::find()
        .filter(entities::orgs::Column::Id.is_in(org_ids))
        .all(&state.orm)
        .await?;
    let orgs_by_id: std::collections::HashMap<Vec<u8>, entities::orgs::Model> =
        orgs.into_iter().map(|o| (o.id.clone(), o)).collect();

    let out = memberships
        .into_iter()
        .filter_map(|m| {
            orgs_by_id.get(&m.org_id).map(|org| {
                let id = Uuid::from_slice(&org.id).expect("orgs.id is BINARY(16)");
                OrgMembershipDto {
                    is_current: id == auth.current_org_id,
                    id,
                    name: org.name.clone(),
                    slug: org.slug.clone(),
                    role: m.role,
                }
            })
        })
        .collect();
    Ok(Json(out))
}

// ─────────────────────────────────────────────────────────────────────
// POST /api/me/switch-org { org_id }
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct SwitchOrgBody {
    pub org_id: Uuid,
}

async fn switch_org(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(token): SessionToken,
    Json(body): Json<SwitchOrgBody>,
) -> Result<Json<AuthedResponse>, AppError> {
    // ensure caller belongs to that org first.
    let belongs = entities::org_users::Entity::find()
        .filter(entities::org_users::Column::UserId.eq(auth.user_id.as_bytes().to_vec()))
        .filter(entities::org_users::Column::OrgId.eq(body.org_id.as_bytes().to_vec()))
        .one(&state.orm)
        .await?;
    if belongs.is_none() {
        return Err(AppError::NotFound);
    }
    switch_session_org(&state.orm, token, body.org_id).await?;

    let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let resp = hydrate_authed(&state.orm, auth.user_id, body.org_id, user.email).await?;
    Ok(Json(resp))
}

// ─────────────────────────────────────────────────────────────────────
// POST /api/orgs { name } — create an additional org for the user
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct CreateOrgBody {
    pub name: String,
}

async fn create_org(
    State(state): State<AppState>,
    auth: AuthContext,
    SessionToken(token): SessionToken,
    Json(body): Json<CreateOrgBody>,
) -> Result<Json<AuthedResponse>, AppError> {
    let name = body.name.trim();
    if name.is_empty() || name.len() > 255 {
        return Err(AppError::BadRequest("name 1..255 chars".into()));
    }
    let slug = make_slug(name);
    let org_id = Uuid::now_v7();
    let ou_id = Uuid::now_v7();

    let txn = state.orm.begin().await?;
    entities::orgs::ActiveModel {
        id: Set(org_id.as_bytes().to_vec()),
        name: Set(name.to_string()),
        slug: Set(slug.clone()),
        ..Default::default()
    }
    .insert(&txn)
    .await?;
    entities::org_users::ActiveModel {
        id: Set(ou_id.as_bytes().to_vec()),
        org_id: Set(org_id.as_bytes().to_vec()),
        user_id: Set(auth.user_id.as_bytes().to_vec()),
        role: Set("owner".into()),
        ..Default::default()
    }
    .insert(&txn)
    .await?;
    txn.commit().await?;

    // switch current_org_id to the freshly-created org — usually what
    // the caller wants right after creation.
    switch_session_org(&state.orm, token, org_id).await?;

    let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::Unauthorized)?;
    let resp = hydrate_authed(&state.orm, auth.user_id, org_id, user.email).await?;
    Ok(Json(resp))
}

fn make_slug(name: &str) -> String {
    // lowercase, ascii-only, dashes for non-alnum, truncated, suffixed
    // with 6 random hex chars so signups don't collide.
    use rand::Rng as _;
    let base: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .chars()
        .take(40)
        .collect();
    let suffix: String = (0..6)
        .map(|_| {
            let n: u8 = rand::thread_rng().gen_range(0..16);
            if n < 10 {
                (b'0' + n) as char
            } else {
                (b'a' + n - 10) as char
            }
        })
        .collect();
    if base.is_empty() {
        format!("org-{suffix}")
    } else {
        format!("{base}-{suffix}")
    }
}
