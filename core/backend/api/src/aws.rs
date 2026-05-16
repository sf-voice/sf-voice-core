//! AWS verification for customer bucket credentials.
//!
//! verify_role: STS AssumeRole with external id → S3 ListObjects in their
//!   bucket. exercises both the trust policy + the permission policy.
//! verify_keys: S3 ListObjects with their access keys directly.
//!
//! both report user-facing errors (BadRequest) when the customer's setup
//! is wrong. Internal only fires on truly broken state (missing env).

use aws_config::{BehaviorVersion, Region};
use aws_credential_types::Credentials;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_sts::Client as StsClient;

use crate::error::AppError;

const SESSION_NAME: &str = "sf-voice-verify";

/// dev escape hatch: if SF_VOICE_SKIP_AWS_VERIFY=1, both functions return
/// Ok() without touching AWS. lets the demo run without aws creds.
fn skip_verify() -> bool {
    std::env::var("SF_VOICE_SKIP_AWS_VERIFY")
        .map(|v| v == "1" || v == "true")
        .unwrap_or(false)
}

pub async fn verify_role(
    role_arn: &str,
    external_id: &str,
    bucket: &str,
    prefix: &str,
    region: &str,
) -> Result<(), AppError> {
    if skip_verify() {
        tracing::warn!("SF_VOICE_SKIP_AWS_VERIFY set — skipping verify_role for {role_arn}");
        return Ok(());
    }

    let region_owned = region.to_string();
    let base = aws_config::defaults(BehaviorVersion::latest())
        .region(Region::new(region_owned.clone()))
        .load()
        .await;
    let sts = StsClient::new(&base);

    let assumed = sts
        .assume_role()
        .role_arn(role_arn)
        .role_session_name(SESSION_NAME)
        .external_id(external_id)
        .duration_seconds(900)
        .send()
        .await
        .map_err(|e| {
            AppError::BadRequest(format!(
                "AssumeRole failed — check the role's trust policy includes our principal + external id ({})",
                short_err(&e)
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
    let s3_conf = aws_sdk_s3::config::Builder::new()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(region_owned))
        .credentials_provider(s3_creds)
        .build();
    let s3 = S3Client::from_conf(s3_conf);

    s3.list_objects_v2()
        .bucket(bucket)
        .prefix(prefix.trim_start_matches('/'))
        .max_keys(1)
        .send()
        .await
        .map_err(|e| {
            AppError::BadRequest(format!(
                "S3 ListObjects on '{bucket}' failed after AssumeRole — check the role's permission policy ({})",
                short_err(&e)
            ))
        })?;
    Ok(())
}

pub async fn verify_keys(
    access_key_id: &str,
    secret_access_key: &str,
    bucket: &str,
    prefix: &str,
    region: &str,
) -> Result<(), AppError> {
    if skip_verify() {
        tracing::warn!("SF_VOICE_SKIP_AWS_VERIFY set — skipping verify_keys for {access_key_id}");
        return Ok(());
    }

    let creds = Credentials::new(
        access_key_id.to_string(),
        secret_access_key.to_string(),
        None,
        None,
        "sf-voice-keys",
    );
    let s3_conf = aws_sdk_s3::config::Builder::new()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(region.to_string()))
        .credentials_provider(creds)
        .build();
    let s3 = S3Client::from_conf(s3_conf);

    s3.list_objects_v2()
        .bucket(bucket)
        .prefix(prefix.trim_start_matches('/'))
        .max_keys(1)
        .send()
        .await
        .map_err(|e| {
            AppError::BadRequest(format!(
                "S3 ListObjects on '{bucket}' failed — check the access key has read access on the bucket ({})",
                short_err(&e)
            ))
        })?;
    Ok(())
}

fn short_err<E: std::fmt::Display>(e: &E) -> String {
    // aws sdk errors are verbose. take the first line, cap at 200 chars.
    let s = e.to_string();
    let line = s.lines().next().unwrap_or(&s);
    if line.len() > 200 {
        format!("{}…", &line[..200])
    } else {
        line.to_string()
    }
}
