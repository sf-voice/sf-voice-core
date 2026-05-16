//! per-org S3 client resolution. reads the org's bucket_* fields and
//! produces an S3 client configured with either:
//!   - assumed-role credentials (method='role'): STS AssumeRole with the
//!     org's external id, returns short-lived creds.
//!   - stored access keys (method='keys'): decrypt with our secrets
//!     key, build static-credentials provider.

use aws_config::{BehaviorVersion, Region};
use aws_credential_types::Credentials;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_sts::Client as StsClient;
use sea_orm::{DatabaseConnection, EntityTrait};
use uuid::Uuid;

use crate::{encryption, error::AppError};

pub struct OrgBucket {
    pub bucket: String,
    pub prefix: String,
    pub region: String,
    pub s3: S3Client,
}

const SESSION_NAME: &str = "sf-voice-ingest";

pub async fn open_for_org(
    db: &DatabaseConnection,
    org_id: Uuid,
) -> Result<OrgBucket, AppError> {
    let org = entities::orgs::Entity::find_by_id(org_id.as_bytes().to_vec())
        .one(db)
        .await?
        .ok_or(AppError::NotFound)?;

    let method = org.bucket_auth_method.ok_or_else(|| {
        AppError::BadRequest("no bucket connected for this org".into())
    })?;
    let bucket = org.bucket_name.ok_or_else(|| {
        AppError::BadRequest("bucket_name missing despite method set".into())
    })?;
    let prefix = org.bucket_prefix.unwrap_or_default();
    let region = org.bucket_region.unwrap_or_else(|| "us-east-1".to_string());

    let s3 = match method.as_str() {
        "role" => {
            let role_arn = org.bucket_role_arn.ok_or_else(|| {
                AppError::BadRequest("bucket_role_arn missing for method=role".into())
            })?;
            let external_id = org.bucket_external_id.ok_or_else(|| {
                AppError::BadRequest("bucket_external_id missing for method=role".into())
            })?;
            s3_for_assumed_role(&role_arn, &external_id, &region).await?
        }
        "keys" => {
            let access_key_id = org.bucket_access_key_id.ok_or_else(|| {
                AppError::BadRequest("bucket_access_key_id missing for method=keys".into())
            })?;
            let encrypted = org.bucket_secret_access_key_encrypted.ok_or_else(|| {
                AppError::BadRequest("bucket_secret_access_key missing for method=keys".into())
            })?;
            let secret_bytes = encryption::decrypt(&encrypted)?;
            let secret = String::from_utf8(secret_bytes)
                .map_err(|e| AppError::Internal(format!("secret decrypt utf8: {e}")))?;
            s3_for_keys(&access_key_id, &secret, &region)
        }
        other => {
            return Err(AppError::Internal(format!(
                "unknown bucket_auth_method '{other}'"
            )))
        }
    };

    Ok(OrgBucket {
        bucket,
        prefix,
        region,
        s3,
    })
}

async fn s3_for_assumed_role(
    role_arn: &str,
    external_id: &str,
    region: &str,
) -> Result<S3Client, AppError> {
    let base = aws_config::defaults(BehaviorVersion::latest())
        .region(Region::new(region.to_string()))
        .load()
        .await;
    let sts = StsClient::new(&base);
    let assumed = sts
        .assume_role()
        .role_arn(role_arn)
        .role_session_name(SESSION_NAME)
        .external_id(external_id)
        .duration_seconds(3600)
        .send()
        .await
        .map_err(|e| {
            AppError::BadRequest(format!(
                "AssumeRole failed for ingest — has the role's trust policy or external id changed? ({e})"
            ))
        })?;
    let creds = assumed
        .credentials
        .ok_or_else(|| AppError::Internal("STS returned no credentials".into()))?;
    let s3_creds = Credentials::new(
        creds.access_key_id.clone(),
        creds.secret_access_key.clone(),
        Some(creds.session_token.clone()),
        None,
        "sf-voice-assumed",
    );
    let conf = aws_sdk_s3::config::Builder::new()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(region.to_string()))
        .credentials_provider(s3_creds)
        .build();
    Ok(S3Client::from_conf(conf))
}

fn s3_for_keys(access_key_id: &str, secret: &str, region: &str) -> S3Client {
    let creds = Credentials::new(
        access_key_id.to_string(),
        secret.to_string(),
        None,
        None,
        "sf-voice-keys",
    );
    let conf = aws_sdk_s3::config::Builder::new()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(region.to_string()))
        .credentials_provider(creds)
        .build();
    S3Client::from_conf(conf)
}
