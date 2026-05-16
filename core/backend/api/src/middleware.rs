//! auth middleware. reads the session cookie on every request and
//! attaches an `AuthContext` to request extensions when valid.
//! handlers that need auth extract `AuthContext` directly; missing
//! context returns 401 via the FromRequestParts impl.

use axum::{
    async_trait,
    extract::{FromRequestParts, State},
    http::{request::Parts, Request},
    middleware::Next,
    response::Response,
};
use axum_extra::extract::CookieJar;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter, QueryOrder};
use uuid::Uuid;

use crate::{
    auth::{
        decode_session_cookie, is_admin_email, load_session, AdminContext, AuthContext,
        SESSION_COOKIE,
    },
    error::AppError,
    state::AppState,
};

/// permissive — sets AuthContext if the cookie is valid, otherwise
/// passes through with nothing attached. handlers decide whether to
/// require auth.
///
/// also honors `?spoof=<email>` for staff: when a sf-voice admin
/// appends it to any request, the AuthContext on that request is
/// rewritten to the spoofed user. SessionToken stays the real one so
/// logout/session-list operations still target the staff member. every
/// successful spoof is logged. non-staff requesting `?spoof=` is just
/// ignored (we don't 403 because URLs sometimes carry stale query
/// strings — staff-only enforcement is sufficient).
pub async fn maybe_auth(
    State(state): State<AppState>,
    jar: CookieJar,
    mut req: Request<axum::body::Body>,
    next: Next,
) -> Response {
    if let Some(cookie) = jar.get(SESSION_COOKIE) {
        if let Some(token) = decode_session_cookie(cookie.value()) {
            if let Ok(mut ctx) = load_session(&state.orm, token).await {
                // resolve a possible ?spoof=email override BEFORE
                // attaching the context so downstream handlers see the
                // already-rewritten user_id + current_org_id.
                if let Some(spoof_email) = spoof_from_query(req.uri().query()) {
                    if let Ok(Some(spoofed)) = resolve_spoof(&state, &ctx, &spoof_email).await {
                        tracing::info!(
                            actor_user_id = %ctx.user_id,
                            spoofed_user_id = %spoofed.user_id,
                            spoofed_org_id = %spoofed.current_org_id,
                            path = %req.uri().path(),
                            "admin spoof"
                        );
                        ctx = spoofed;
                    }
                }
                req.extensions_mut().insert(ctx);
                // also stash the raw token so logout/switch handlers
                // can mutate the session row without re-decoding.
                req.extensions_mut().insert(SessionToken(token));
            }
        }
    }
    next.run(req).await
}

#[derive(Clone, Copy)]
pub struct SessionToken(pub [u8; 32]);

/// pull `spoof` out of the query string without dragging in a url-parser.
/// returns the first occurrence; no decoding beyond `+` → ` `.
fn spoof_from_query(q: Option<&str>) -> Option<String> {
    let q = q?;
    for pair in q.split('&') {
        let mut parts = pair.splitn(2, '=');
        let key = parts.next()?;
        if key != "spoof" {
            continue;
        }
        let v = parts.next()?;
        // very permissive decode — emails don't contain `%` or `+` in
        // practice, but axum routers sometimes encode anyway.
        let decoded = urlencoding::decode(v).ok()?.into_owned();
        if decoded.is_empty() {
            return None;
        }
        return Some(decoded);
    }
    None
}

/// look up the spoofed user IF the actor is staff. returns None when:
///   - the actor isn't staff (silent ignore, see maybe_auth doc)
///   - the spoofed email doesn't resolve to a user
///   - the spoofed user has no org memberships
async fn resolve_spoof(
    state: &AppState,
    actor: &AuthContext,
    spoof_email: &str,
) -> Result<Option<AuthContext>, AppError> {
    // actor must be staff
    let actor_user = entities::users::Entity::find_by_id(actor.user_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?;
    let Some(actor_user) = actor_user else {
        return Ok(None);
    };
    if !is_admin_email(&actor_user.email) {
        return Ok(None);
    }

    // resolve the spoofed user
    let spoofed_user = entities::users::Entity::find()
        .filter(entities::users::Column::Email.eq(spoof_email.to_ascii_lowercase()))
        .one(&state.orm)
        .await?;
    let Some(spoofed_user) = spoofed_user else {
        return Ok(None);
    };

    // and a default org membership (oldest first)
    let membership = entities::org_users::Entity::find()
        .filter(entities::org_users::Column::UserId.eq(spoofed_user.id.clone()))
        .order_by_asc(entities::org_users::Column::CreatedAt)
        .one(&state.orm)
        .await?;
    let Some(membership) = membership else {
        return Ok(None);
    };

    Ok(Some(AuthContext {
        user_id: Uuid::from_slice(&spoofed_user.id)
            .map_err(|e| AppError::Internal(e.to_string()))?,
        current_org_id: Uuid::from_slice(&membership.org_id)
            .map_err(|e| AppError::Internal(e.to_string()))?,
    }))
}

// AuthContext extractor: returns 401 when the middleware didn't
// attach a context for this request. axum-core 0.4 wraps the trait in
// #[async_trait], so impls must too — plain `async fn` won't match
// lifetimes otherwise (E0195).
#[async_trait]
impl<S> FromRequestParts<S> for AuthContext
where
    S: Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<AuthContext>()
            .cloned()
            .ok_or(AppError::Unauthorized)
    }
}

#[async_trait]
impl<S> FromRequestParts<S> for SessionToken
where
    S: Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<SessionToken>()
            .copied()
            .ok_or(AppError::Unauthorized)
    }
}

// AdminContext extractor: builds on AuthContext (already attached by
// maybe_auth above), looks up the user's email, gates on the
// @sf-voice.sh suffix.
//   - no session  → 401 (handled by AuthContext missing)
//   - wrong email → 403 (forbidden, so the frontend doesn't redirect to /login)
// the email lookup is per-request — fine for admin routes which are
// low-traffic. if we ever cache email on the session row, swap to that.
#[async_trait]
impl FromRequestParts<AppState> for AdminContext {
    type Rejection = AppError;
    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .extensions
            .get::<AuthContext>()
            .cloned()
            .ok_or(AppError::Unauthorized)?;

        let user = entities::users::Entity::find_by_id(auth.user_id.as_bytes().to_vec())
            .one(&state.orm)
            .await?
            .ok_or(AppError::Unauthorized)?;

        if !is_admin_email(&user.email) {
            return Err(AppError::Forbidden);
        }

        Ok(AdminContext {
            user_id: auth.user_id,
            current_org_id: auth.current_org_id,
            email: user.email,
        })
    }
}
