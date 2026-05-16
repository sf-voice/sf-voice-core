use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64URL, Engine as _};
use chrono::Utc;
use rand::RngCore;
use sea_orm::{
    ActiveModelTrait,
    ActiveValue::{NotSet, Set},
    EntityTrait,
};
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
    let org = entities::orgs::Entity::find_by_id(auth.current_org_id.as_bytes().to_vec())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;

    Ok(Json(BucketStatus {
        method: org.bucket_auth_method,
        bucket_name: org.bucket_name,
        bucket_prefix: org.bucket_prefix,
        bucket_region: org.bucket_region,
        bucket_account_id: org.bucket_account_id,
        bucket_role_arn: org.bucket_role_arn,
        bucket_access_key_id: org.bucket_access_key_id,
        bucket_external_id: org.bucket_external_id,
        verified_at: org
            .bucket_verified_at
            .map(|t| chrono::DateTime::<Utc>::from_naive_utc_and_offset(t, Utc)),
    }))
}

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

    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();
    let org = entities::orgs::Entity::find_by_id(org_id_bytes.clone())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;

    let external_id = match org.bucket_external_id.clone() {
        Some(eid) => eid,
        None => generate_external_id(),
    };

    let mut active = entities::orgs::ActiveModel {
        id: Set(org_id_bytes),
        ..Default::default()
    };
    if org.bucket_external_id.is_none() {
        active.bucket_external_id = Set(Some(external_id.clone()));
    }
    if !bucket_name.is_empty() {
        active.bucket_name = Set(Some(bucket_name.clone()));
    }
    if !bucket_prefix.is_empty() {
        active.bucket_prefix = Set(Some(bucket_prefix.clone()));
    }
    if !region.is_empty() {
        active.bucket_region = Set(Some(region.clone()));
    }
    if !account_id.is_empty() {
        active.bucket_account_id = Set(Some(account_id));
    }
    active.update(&state.orm).await?;

    Ok(Json(SetupResponse {
        quick_create_url: quick_create_url(&region, &external_id, &bucket_name, &bucket_prefix),
        external_id,
        aws_principal: our_aws_principal(),
        template_url: template_url(),
    }))
}

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
        return Err(AppError::BadRequest(
            "role_arn must start with arn:aws:iam::".into(),
        ));
    }

    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();
    let org = entities::orgs::Entity::find_by_id(org_id_bytes.clone())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    let external_id = org.bucket_external_id.ok_or_else(|| {
        AppError::BadRequest("no external_id on this org — open AWS console step first".into())
    })?;

    let bucket_prefix = body.bucket_prefix.as_deref().unwrap_or("");

    aws::verify_role(
        &body.role_arn,
        &external_id,
        &body.bucket_name,
        bucket_prefix,
        &body.bucket_region,
    )
    .await?;

    entities::orgs::ActiveModel {
        id: Set(org_id_bytes),
        bucket_auth_method: Set(Some("role".into())),
        bucket_name: Set(Some(body.bucket_name)),
        bucket_prefix: Set(Some(bucket_prefix.to_string())),
        bucket_region: Set(Some(body.bucket_region)),
        bucket_role_arn: Set(Some(body.role_arn)),
        // clear stored-keys fields when switching to role
        bucket_access_key_id: Set(None),
        bucket_secret_access_key_encrypted: Set(None),
        bucket_verified_at: Set(Some(Utc::now().naive_utc())),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;

    get_status(State(state), auth).await
}

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
    Verified {
        role_arn: String,
        bucket: BucketStatus,
    },
    Pending {
        role_arn: String,
        reason: String,
    },
    Failed {
        role_arn: String,
        reason: String,
    },
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
    let role_arn = format!("arn:aws:iam::{account_id}:role/sf-voice-readonly-sf-voice-readonly");

    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();
    let org = entities::orgs::Entity::find_by_id(org_id_bytes.clone())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    let external_id = org.bucket_external_id.ok_or_else(|| {
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
            entities::orgs::ActiveModel {
                id: Set(org_id_bytes),
                bucket_auth_method: Set(Some("role".into())),
                bucket_name: Set(Some(body.bucket_name)),
                bucket_prefix: Set(Some(bucket_prefix.to_string())),
                bucket_region: Set(Some(body.bucket_region)),
                bucket_account_id: Set(Some(account_id.to_string())),
                bucket_role_arn: Set(Some(role_arn.clone())),
                bucket_access_key_id: Set(None),
                bucket_secret_access_key_encrypted: Set(None),
                bucket_verified_at: Set(Some(Utc::now().naive_utc())),
                ..Default::default()
            }
            .update(&state.orm)
            .await?;
            let bucket = get_status(State(state), auth).await?.0;
            Ok(Json(ProbeRoleResponse::Verified { role_arn, bucket }))
        }
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

    entities::orgs::ActiveModel {
        id: Set(auth.current_org_id.as_bytes().to_vec()),
        bucket_auth_method: Set(Some("keys".into())),
        bucket_name: Set(Some(body.bucket_name)),
        bucket_prefix: Set(Some(bucket_prefix.to_string())),
        bucket_region: Set(Some(body.bucket_region)),
        bucket_access_key_id: Set(Some(body.access_key_id)),
        bucket_secret_access_key_encrypted: Set(Some(encrypted)),
        // clear role fields when switching to keys
        bucket_role_arn: Set(None),
        bucket_verified_at: Set(Some(Utc::now().naive_utc())),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;

    get_status(State(state), auth).await
}

async fn disconnect(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<BucketStatus>, AppError> {
    entities::orgs::ActiveModel {
        id: Set(auth.current_org_id.as_bytes().to_vec()),
        bucket_auth_method: Set(None),
        bucket_name: Set(None),
        bucket_prefix: Set(None),
        bucket_region: Set(None),
        bucket_role_arn: Set(None),
        bucket_access_key_id: Set(None),
        bucket_secret_access_key_encrypted: Set(None),
        bucket_verified_at: Set(None),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;
    get_status(State(state), auth).await
}

#[derive(Debug, Serialize)]
pub struct IngestEnqueuedResponse {
    pub job_id: uuid::Uuid,
}

async fn ingest_now(
    State(state): State<AppState>,
    auth: AuthContext,
) -> Result<Json<IngestEnqueuedResponse>, AppError> {
    let org_id_bytes = auth.current_org_id.as_bytes().to_vec();
    let org = entities::orgs::Entity::find_by_id(org_id_bytes.clone())
        .one(&state.orm)
        .await?
        .ok_or(AppError::NotFound)?;
    let method = org
        .bucket_auth_method
        .ok_or_else(|| AppError::BadRequest("no bucket connected for this org".into()))?;
    tracing::info!(org_id = %auth.current_org_id, %method, "ingest enqueue");

    let job_id = uuid::Uuid::now_v7();
    entities::jobs::ActiveModel {
        id: Set(job_id.as_bytes().to_vec()),
        org_id: Set(org_id_bytes.clone()),
        kind: Set("ingest".into()),
        subject_type: Set("org".into()),
        subject_id: Set(Some(org_id_bytes)),
        status: Set("queued".into()),
        payload: NotSet,
        ..Default::default()
    }
    .insert(&state.orm)
    .await?;

    Ok(Json(IngestEnqueuedResponse { job_id }))
}
async fn template_yaml() -> impl axum::response::IntoResponse {
    (
        [(axum::http::header::CONTENT_TYPE, "application/x-yaml")],
        TEMPLATE_YAML,
    )
}

fn generate_external_id() -> String {
    let mut bytes = [0u8; 24];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!("sfv-{}", B64URL.encode(bytes))
}
