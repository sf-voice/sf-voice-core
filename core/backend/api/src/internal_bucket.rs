//! sf-voice-owned bucket resolver for internal-only writes.
//!
//! distinct from `aws_creds::open_for_org` — that resolves the customer's
//! bucket from their `orgs.bucket_*` columns. this one points at the
//! sf-voice-owned bucket, scoped to a top-level `internal/` prefix so
//! admin-tool data stays isolated from anything else in the same bucket.
//!
//! reuses the existing repo-wide aws env: `S3_BUCKET_NAME` for the
//! bucket, `AWS_REGION` for the region, and the standard aws sdk
//! provider chain (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` or an
//! IAM role) for credentials. no new env vars introduced for this.

use aws_config::{BehaviorVersion, Region};
use aws_sdk_s3::Client as S3Client;

use crate::error::AppError;

/// top-level prefix every internal write goes under. hardcoded — there's
/// only one internal context, and routing through env makes a one-liner
/// look more configurable than it is.
const INTERNAL_PREFIX: &str = "internal";

pub struct InternalBucket {
    pub bucket: String,
    /// top-level prefix, no trailing slash. callers join their own
    /// sub-keys onto this.
    pub prefix: String,
    pub region: String,
    pub s3: S3Client,
}

pub async fn open() -> Result<InternalBucket, AppError> {
    let bucket = std::env::var("S3_BUCKET_NAME").map_err(|_| {
        AppError::Internal("S3_BUCKET_NAME not set".into())
    })?;
    let region = std::env::var("AWS_REGION").map_err(|_| {
        AppError::Internal("AWS_REGION not set".into())
    })?;

    let conf = aws_config::defaults(BehaviorVersion::latest())
        .region(Region::new(region.clone()))
        .load()
        .await;
    let s3 = S3Client::new(&conf);

    Ok(InternalBucket {
        bucket,
        prefix: INTERNAL_PREFIX.to_string(),
        region,
        s3,
    })
}
