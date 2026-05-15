//! /api/org/bucket/* — connect a customer's S3 bucket. two methods:
//!
//! - IAM role assumption (recommended): we generate an external_id; the
//!   customer creates a role with our principal + that external id in
//!   the trust policy. they paste back the role arn.
//!
//! - stored access keys: we encrypt the secret with xchacha20poly1305.
//!
//! v1 doesn't verify creds at save time — the heavy aws-sdk crates
//! aren't in the build yet. first ingest job (phase C) will verify and
//! stamp bucket_verified_at on success.

use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64URL, Engine as _};
use rand::RngCore;
use serde::{Deserialize, Serialize};

use crate::{
    auth::AuthContext,
    aws,
    cloudformation::{our_aws_principal, quick_create_url, template_url, TEMPLATE_YAML},
    encryption,
    error::AppError,
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/org/bucket", get(get_status).delete(disconnect))
        .route("/org/bucket/role", post(save_role))
        .route("/org/bucket/role/probe", post(probe_role))
        .route("/org/bucket/keys", post(save_keys))
        .route("/org/bucket/setup", get(setup_info))
        .route("/org/bucket/ingest", post(ingest_now))
        .route("/cfn/sf-voice-readonly.yaml", get(template_yaml))
}

// ─────────────────────────────────────────────────────────────────────
// GET /api/org/bucket — current status
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct BucketStatus {
    pub method: Option<String>, // "role" | "keys" | null
    pub bucket_name: Option<String>,
    pub bucket_prefix: Option<String>,
    pub bucket_region: Option<String>,
    pub bucket_account_id: Option<String>,
    pub bucket_role_arn: Option<String>,
    pub bucket_access_key_id: Option<String>,
    pub bucket_external_id: Option<String>,
    pub verified_at: Option<chrono::DateTime<chrono::Utc>>,
}

async fn get_status(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<BucketStatus>, AppError> {
    let row: Option<(
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<chrono::DateTime<chrono::Utc>>,
    )> = sqlx::query_as(
        r#"
        SELECT bucket_auth_method,
               bucket_name, bucket_prefix, bucket_region, bucket_account_id,
               bucket_role_arn, bucket_access_key_id,
               bucket_external_id, bucket_verified_at
        FROM orgs WHERE id = ?
        "#,
    )
    .bind(auth.current_org_id.as_bytes().as_slice())
    .fetch_optional(&state.pool)
    .await?;

    let r = row.ok_or(AppError::NotFound)?;
    Ok(Json(BucketStatus {
        method: r.0,
        bucket_name: r.1,
        bucket_prefix: r.2,
        bucket_region: r.3,
        bucket_account_id: r.4,
        bucket_role_arn: r.5,
        bucket_access_key_id: r.6,
        bucket_external_id: r.7,
        verified_at: r.8,
    }))
}

// ─────────────────────────────────────────────────────────────────────
// GET /api/org/bucket/setup — one-click params (external_id, cfn url)
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct SetupQuery {
    pub bucket_name: Option<String>,
    pub bucket_prefix: Option<String>,
    pub bucket_region: Option<String>,
    pub aws_account_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SetupResponse {
    pub external_id: String,
    pub aws_principal: String,
    pub template_url: String,
    pub quick_create_url: String,
}

/// idempotently generates an external_id for this org (or returns the
/// existing one), persists the form values as a draft so a refresh
/// doesn't wipe them, and assembles the cloudformation quick-create url.
async fn setup_info(
    State(state): State<AppState>,
    auth: AuthContext,
    axum::extract::Query(q): axum::extract::Query<SetupQuery>,
) -> Result<Json<SetupResponse>, AppError> {
    let bucket_name = q.bucket_name.unwrap_or_default();
    let bucket_prefix = q.bucket_prefix.unwrap_or_default();
    let region = q.bucket_region.unwrap_or_else(|| "us-east-1".into());
    let account_id = q.aws_account_id.unwrap_or_default();

    // fetch + lazy-create external_id, then persist the draft form fields
    // on the same row. only sets fields the caller actually provided so
    // we don't clobber a verified connection if the wizard rehydrates
    // with empty strings mid-edit.
    let existing: Option<(Option<String>,)> =
        sqlx::query_as("SELECT bucket_external_id FROM orgs WHERE id = ?")
            .bind(auth.current_org_id.as_bytes().as_slice())
            .fetch_optional(&state.pool)
            .await?;
    let external_id = match existing.and_then(|(eid,)| eid) {
        Some(eid) => eid,
        None => {
            let new = generate_external_id();
            sqlx::query("UPDATE orgs SET bucket_external_id = ? WHERE id = ?")
                .bind(&new)
                .bind(auth.current_org_id.as_bytes().as_slice())
                .execute(&state.pool)
                .await?;
            new
        }
    };

    // autosave: each call to /setup also persists the latest form draft.
    // COALESCE on empties keeps previously-saved values when the caller
    // omits a field, so partial calls don't blow away other fields.
    sqlx::query(
        r#"
        UPDATE orgs SET
          bucket_name       = COALESCE(NULLIF(?, ''), bucket_name),
          bucket_prefix     = COALESCE(NULLIF(?, ''), bucket_prefix),
          bucket_region     = COALESCE(NULLIF(?, ''), bucket_region),
          bucket_account_id = COALESCE(NULLIF(?, ''), bucket_account_id)
        WHERE id = ?
        "#,
    )
    .bind(&bucket_name)
    .bind(&bucket_prefix)
    .bind(&region)
    .bind(&account_id)
    .bind(auth.current_org_id.as_bytes().as_slice())
    .execute(&state.pool)
    .await?;

    Ok(Json(SetupResponse {
        quick_create_url: quick_create_url(&region, &external_id, &bucket_name, &bucket_prefix),
        external_id,
        aws_principal: our_aws_principal(),
        template_url: template_url(),
    }))
}

// ─────────────────────────────────────────────────────────────────────
// POST /api/org/bucket/role — IAM role assumption setup
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct SaveRoleBody {
    pub bucket_name: String,
    pub bucket_prefix: Option<String>,
    pub bucket_region: String,
    pub role_arn: String,
}

async fn save_role(
    State(state): State<AppState>,
    auth: AuthContext,
    Json(body): Json<SaveRoleBody>,
) -> Result<Json<BucketStatus>, AppError> {
    if body.bucket_name.trim().is_empty()
        || body.bucket_region.trim().is_empty()
        || body.role_arn.trim().is_empty()
    {
        return Err(AppError::BadRequest(
            "bucket_name, bucket_region, role_arn required".into(),
        ));
    }
    if !body.role_arn.starts_with("arn:aws:iam::") {
        return Err(AppError::BadRequest("role_arn must start with arn:aws:iam::".into()));
    }

    // we need the org's external_id to call AssumeRole. fetch + create
    // if it doesn't exist yet — most users will have hit /setup before
    // landing here, so this is usually a no-op.
    let existing: Option<(Option<String>,)> =
        sqlx::query_as("SELECT bucket_external_id FROM orgs WHERE id = ?")
            .bind(auth.current_org_id.as_bytes().as_slice())
            .fetch_optional(&state.pool)
            .await?;
    let external_id = match existing.and_then(|(eid,)| eid) {
        Some(eid) => eid,
        None => {
            return Err(AppError::BadRequest(
                "no external_id on this org — open AWS console step first".into(),
            ));
        }
    };

    let bucket_prefix = body.bucket_prefix.as_deref().unwrap_or("");

    // verify before persisting. AssumeRole with external_id → S3
    // ListObjects. failure returns a customer-facing error explaining
    // which step failed.
    aws::verify_role(
        &body.role_arn,
        &external_id,
        &body.bucket_name,
        bucket_prefix,
        &body.bucket_region,
    )
    .await?;

    sqlx::query(
        r#"
        UPDATE orgs SET
          bucket_auth_method = 'role',
          bucket_name        = ?,
          bucket_prefix      = ?,
          bucket_region      = ?,
          bucket_role_arn    = ?,
          -- clear stored-keys fields when switching to role
          bucket_access_key_id = NULL,
          bucket_secret_access_key_encrypted = NULL,
          bucket_verified_at = CURRENT_TIMESTAMP
        WHERE id = ?
        "#,
    )
    .bind(&body.bucket_name)
    .bind(bucket_prefix)
    .bind(&body.bucket_region)
    .bind(&body.role_arn)
    .bind(auth.current_org_id.as_bytes().as_slice())
    .execute(&state.pool)
    .await?;

    get_status(State(state), auth).await
}

// ─────────────────────────────────────────────────────────────────────
// POST /api/org/bucket/role/probe — auto-discover stack completion
//
// the frontend wizard polls this every few seconds after the customer
// opens the AWS console. given the account id (and bucket details), we
// know the Role ARN deterministically because the CFN template uses
// a fixed role name. each probe call tries STS AssumeRole + S3 ListObjects;
// when it works, we persist exactly as /role would. callers can stop
// polling on `verified` or `failed`; `pending` means stack is still
// provisioning (or wasn't created yet).
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ProbeRoleBody {
    pub aws_account_id: String,
    pub bucket_name: String,
    pub bucket_prefix: Option<String>,
    pub bucket_region: String,
}

#[derive(Debug, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum ProbeRoleResponse {
    Verified { role_arn: String, bucket: BucketStatus },
    Pending { role_arn: String, reason: String },
    Failed { role_arn: String, reason: String },
}

async fn probe_role(
    State(state): State<AppState>,
    auth: AuthContext,
    Json(body): Json<ProbeRoleBody>,
) -> Result<Json<ProbeRoleResponse>, AppError> {
    let account_id = body.aws_account_id.trim();
    if account_id.len() != 12 || !account_id.chars().all(|c| c.is_ascii_digit()) {
        return Err(AppError::BadRequest(
            "aws_account_id must be exactly 12 digits".into(),
        ));
    }
    if body.bucket_name.trim().is_empty() || body.bucket_region.trim().is_empty() {
        return Err(AppError::BadRequest(
            "bucket_name and bucket_region required".into(),
        ));
    }

    // role name is fixed by the CFN template — see cloudformation.rs.
    // template uses `sf-voice-readonly-${AWS::StackName}` and we always
    // create the stack as `sf-voice-readonly`. so role name is determined.
    let role_arn = format!("arn:aws:iam::{account_id}:role/sf-voice-readonly-sf-voice-readonly");

    let existing: Option<(Option<String>,)> =
        sqlx::query_as("SELECT bucket_external_id FROM orgs WHERE id = ?")
            .bind(auth.current_org_id.as_bytes().as_slice())
            .fetch_optional(&state.pool)
            .await?;
    let external_id = existing.and_then(|(eid,)| eid).ok_or_else(|| {
        AppError::BadRequest("no external_id on this org — open AWS console step first".into())
    })?;

    let bucket_prefix = body.bucket_prefix.as_deref().unwrap_or("");

    match aws::verify_role(
        &role_arn,
        &external_id,
        &body.bucket_name,
        bucket_prefix,
        &body.bucket_region,
    )
    .await
    {
        Ok(()) => {
            sqlx::query(
                r#"
                UPDATE orgs SET
                  bucket_auth_method = 'role',
                  bucket_name        = ?,
                  bucket_prefix      = ?,
                  bucket_region      = ?,
                  bucket_account_id  = ?,
                  bucket_role_arn    = ?,
                  bucket_access_key_id = NULL,
                  bucket_secret_access_key_encrypted = NULL,
                  bucket_verified_at = CURRENT_TIMESTAMP
                WHERE id = ?
                "#,
            )
            .bind(&body.bucket_name)
            .bind(bucket_prefix)
            .bind(&body.bucket_region)
            .bind(account_id)
            .bind(&role_arn)
            .bind(auth.current_org_id.as_bytes().as_slice())
            .execute(&state.pool)
            .await?;
            let bucket = get_status(State(state), auth).await?.0;
            Ok(Json(ProbeRoleResponse::Verified { role_arn, bucket }))
        }
        // mid-provision: role doesn't exist yet, or trust policy hasn't
        // propagated. these are the "keep polling" cases. anything else
        // (access denied with wrong external id, etc.) is terminal.
        Err(AppError::BadRequest(msg)) => {
            let pending = msg.contains("NoSuchEntity")
                || msg.contains("does not exist")
                || msg.contains("not authorized to perform: sts:AssumeRole on resource");
            if pending {
                Ok(Json(ProbeRoleResponse::Pending {
                    role_arn,
                    reason: msg,
                }))
            } else {
                Ok(Json(ProbeRoleResponse::Failed {
                    role_arn,
                    reason: msg,
                }))
            }
        }
        Err(e) => Err(e),
    }
}

// ─────────────────────────────────────────────────────────────────────
// POST /api/org/bucket/keys — stored access keys
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct SaveKeysBody {
    pub bucket_name: String,
    pub bucket_prefix: Option<String>,
    pub bucket_region: String,
    pub access_key_id: String,
    pub secret_access_key: String,
}

async fn save_keys(
    State(state): State<AppState>,
    auth: AuthContext,
    Json(body): Json<SaveKeysBody>,
) -> Result<Json<BucketStatus>, AppError> {
    if body.bucket_name.trim().is_empty()
        || body.bucket_region.trim().is_empty()
        || body.access_key_id.trim().is_empty()
        || body.secret_access_key.trim().is_empty()
    {
        return Err(AppError::BadRequest(
            "bucket_name, bucket_region, access_key_id, secret_access_key required".into(),
        ));
    }

    let bucket_prefix = body.bucket_prefix.as_deref().unwrap_or("");

    // verify before persisting. S3 ListObjects with the customer's
    // keys. on failure the keys never touch the database.
    aws::verify_keys(
        &body.access_key_id,
        &body.secret_access_key,
        &body.bucket_name,
        bucket_prefix,
        &body.bucket_region,
    )
    .await?;

    let encrypted = encryption::encrypt(body.secret_access_key.as_bytes())?;

    sqlx::query(
        r#"
        UPDATE orgs SET
          bucket_auth_method = 'keys',
          bucket_name        = ?,
          bucket_prefix      = ?,
          bucket_region      = ?,
          bucket_access_key_id = ?,
          bucket_secret_access_key_encrypted = ?,
          -- clear role fields when switching to keys
          bucket_role_arn = NULL,
          bucket_verified_at = CURRENT_TIMESTAMP
        WHERE id = ?
        "#,
    )
    .bind(&body.bucket_name)
    .bind(bucket_prefix)
    .bind(&body.bucket_region)
    .bind(&body.access_key_id)
    .bind(&encrypted)
    .bind(auth.current_org_id.as_bytes().as_slice())
    .execute(&state.pool)
    .await?;

    get_status(State(state), auth).await
}

// ─────────────────────────────────────────────────────────────────────
// DELETE /api/org/bucket — disconnect (clears all bucket fields)
// ─────────────────────────────────────────────────────────────────────

async fn disconnect(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<BucketStatus>, AppError> {
    sqlx::query(
        r#"
        UPDATE orgs SET
          bucket_auth_method = NULL,
          bucket_name = NULL,
          bucket_prefix = NULL,
          bucket_region = NULL,
          bucket_role_arn = NULL,
          bucket_access_key_id = NULL,
          bucket_secret_access_key_encrypted = NULL,
          bucket_verified_at = NULL
        WHERE id = ?
        "#,
    )
    .bind(auth.current_org_id.as_bytes().as_slice())
    .execute(&state.pool)
    .await?;
    get_status(State(state), auth).await
}

// ─────────────────────────────────────────────────────────────────────
// POST /api/org/bucket/ingest — enqueue an ingest job for the current org
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct IngestEnqueuedResponse {
    pub job_id: uuid::Uuid,
}

async fn ingest_now(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<IngestEnqueuedResponse>, AppError> {
    // gate: the org must have a bucket configured. avoids a job that
    // would fail at the first aws_creds lookup.
    let configured: Option<(Option<String>,)> =
        sqlx::query_as("SELECT bucket_auth_method FROM orgs WHERE id = ?")
            .bind(auth.current_org_id.as_bytes().as_slice())
            .fetch_optional(&state.pool)
            .await?;
    let method = configured
        .and_then(|(m,)| m)
        .ok_or_else(|| AppError::BadRequest("no bucket connected for this org".into()))?;
    tracing::info!(org_id = %auth.current_org_id, %method, "ingest enqueue");

    let job_id = uuid::Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO jobs (id, org_id, kind, subject_type, subject_id, status, created_at)
        VALUES (?, ?, 'ingest', 'org', ?, 'queued', CURRENT_TIMESTAMP)
        "#,
    )
    .bind(job_id.as_bytes().as_slice())
    .bind(auth.current_org_id.as_bytes().as_slice())
    .bind(auth.current_org_id.as_bytes().as_slice())
    .execute(&state.pool)
    .await?;

    Ok(Json(IngestEnqueuedResponse { job_id }))
}

// ─────────────────────────────────────────────────────────────────────
// GET /cfn/sf-voice-readonly.yaml — serve the cloudformation template
// ─────────────────────────────────────────────────────────────────────

async fn template_yaml() -> impl axum::response::IntoResponse {
    (
        [(axum::http::header::CONTENT_TYPE, "application/x-yaml")],
        TEMPLATE_YAML,
    )
}

// ─────────────────────────────────────────────────────────────────────
// helpers
// ─────────────────────────────────────────────────────────────────────

fn generate_external_id() -> String {
    // 24 bytes → 32 chars url-safe base64. plenty of entropy; short
    // enough to fit in our 128-char column.
    let mut bytes = [0u8; 24];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!("sfv-{}", B64URL.encode(bytes))
}
