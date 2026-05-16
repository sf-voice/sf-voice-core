//! download-and-verify bootstrap for ggml/onnx model files.
//! intentionally no ml deps here

use std::path::{Path, PathBuf};

use aws_config::BehaviorVersion;
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;

use crate::error::AppError;

/// every model file the api may need, resolved to a verified local
/// path. consumers grab the field for whichever stage they own.
#[derive(Debug, Clone)]
pub struct ModelPaths {
    pub whisper: PathBuf,
    pub bge_m3_model: PathBuf,
    pub bge_m3_tokenizer: PathBuf,
    pub bge_m3_config: PathBuf,
    pub bge_m3_special_tokens: PathBuf,
    pub diar_segmentation: PathBuf,
    pub diar_embedding: PathBuf,
}

// one entry per file we mirror. rel = key suffix under prefix; matches
// the on-disk layout under MODELS_DIR. sha_sidecar=true means a sibling
// `<rel>.sha256` exists in s3 and we verify against it.
struct Spec {
    rel: &'static str,
    sha_sidecar: bool,
}

const SPEC_WHISPER: usize = 0;
const SPEC_BGE_MODEL: usize = 1;
const SPEC_BGE_TOKENIZER: usize = 2;
const SPEC_BGE_CONFIG: usize = 3;
const SPEC_BGE_SPECIAL: usize = 4;
const SPEC_DIAR_SEG: usize = 5;
const SPEC_DIAR_EMB: usize = 6;

const SPECS: &[Spec] = &[
    Spec {
        rel: "whisper/ggml-large-v3-turbo-q5_0.bin",
        sha_sidecar: true,
    },
    Spec {
        rel: "bge-m3/model_quantized.onnx",
        sha_sidecar: false,
    },
    Spec {
        rel: "bge-m3/tokenizer.json",
        sha_sidecar: false,
    },
    Spec {
        rel: "bge-m3/config.json",
        sha_sidecar: false,
    },
    Spec {
        rel: "bge-m3/special_tokens_map.json",
        sha_sidecar: false,
    },
    Spec {
        rel: "diarization/segmentation-3.0.onnx",
        sha_sidecar: false,
    },
    Spec {
        rel: "diarization/embedding-eres2netv2.onnx",
        sha_sidecar: false,
    },
];

pub async fn bootstrap() -> Result<ModelPaths, AppError> {
    let cfg = Config::from_env()?;
    std::fs::create_dir_all(&cfg.models_dir)
        .map_err(|e| AppError::Internal(format!("create MODELS_DIR {:?}: {e}", cfg.models_dir)))?;

    let s3 = s3_client(&cfg).await;

    for spec in SPECS {
        let local = cfg.models_dir.join(spec.rel);
        if let Some(parent) = local.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| AppError::Internal(format!("mkdir {parent:?}: {e}")))?;
        }
        ensure_present(&s3, &cfg, spec, &local).await?;
    }

    let p = |i: usize| cfg.models_dir.join(SPECS[i].rel);
    Ok(ModelPaths {
        whisper: p(SPEC_WHISPER),
        bge_m3_model: p(SPEC_BGE_MODEL),
        bge_m3_tokenizer: p(SPEC_BGE_TOKENIZER),
        bge_m3_config: p(SPEC_BGE_CONFIG),
        bge_m3_special_tokens: p(SPEC_BGE_SPECIAL),
        diar_segmentation: p(SPEC_DIAR_SEG),
        diar_embedding: p(SPEC_DIAR_EMB),
    })
}

struct Config {
    models_dir: PathBuf,
    bucket: String,
    prefix: String,
    region: Option<String>,
}

impl Config {
    fn from_env() -> Result<Self, AppError> {
        // default to a project-local cache for dev; production sets
        // MODELS_DIR to a persistent path (e.g. /var/lib/sf-voice/models).
        let models_dir: PathBuf = std::env::var("MODELS_DIR")
            .unwrap_or_else(|_| "./.models".into())
            .into();
        let bucket = std::env::var("MODELS_S3_BUCKET")
            .map_err(|_| AppError::Internal("MODELS_S3_BUCKET not set".into()))?;
        let prefix = std::env::var("MODELS_S3_PREFIX").unwrap_or_else(|_| "sf-voice-models".into());
        let region = std::env::var("MODELS_S3_REGION").ok();
        Ok(Self {
            models_dir,
            bucket,
            prefix,
            region,
        })
    }
}

async fn s3_client(cfg: &Config) -> aws_sdk_s3::Client {
    let mut loader = aws_config::defaults(BehaviorVersion::latest());
    if let Some(r) = &cfg.region {
        loader = loader.region(aws_config::Region::new(r.clone()));
    }
    let sdk = loader.load().await;
    aws_sdk_s3::Client::new(&sdk)
}

async fn ensure_present(
    s3: &aws_sdk_s3::Client,
    cfg: &Config,
    spec: &Spec,
    local: &Path,
) -> Result<(), AppError> {
    // if a sidecar sha exists, fetch it once — we use it for both the
    // "is the local copy still valid?" check and the post-download verify.
    let expected_sha = if spec.sha_sidecar {
        Some(fetch_sha(s3, cfg, spec).await?)
    } else {
        None
    };

    if local.exists() {
        match &expected_sha {
            Some(exp) => {
                let got =
                    sha_of(local).map_err(|e| AppError::Internal(format!("sha {local:?}: {e}")))?;
                if &got == exp {
                    tracing::info!(file = ?local, "model present, sha ok");
                    return Ok(());
                }
                tracing::warn!(file = ?local, "model sha mismatch — re-downloading");
            }
            None => {
                tracing::info!(file = ?local, "model present (no sha sidecar to verify)");
                return Ok(());
            }
        }
    }

    let key = format!("{}/{}", cfg.prefix, spec.rel);
    tracing::info!(bucket = %cfg.bucket, key = %key, dst = ?local, "downloading model");
    download_to(s3, &cfg.bucket, &key, local).await?;

    if let Some(exp) = expected_sha {
        let got =
            sha_of(local).map_err(|e| AppError::Internal(format!("post-download sha: {e}")))?;
        if got != exp {
            return Err(AppError::Internal(format!(
                "downloaded model sha mismatch for {key}: got {got}, expected {exp}"
            )));
        }
    }
    Ok(())
}

async fn fetch_sha(s3: &aws_sdk_s3::Client, cfg: &Config, spec: &Spec) -> Result<String, AppError> {
    let key = format!("{}/{}.sha256", cfg.prefix, spec.rel);
    let resp = s3
        .get_object()
        .bucket(&cfg.bucket)
        .key(&key)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("get s3://{}/{key}: {e}", cfg.bucket)))?;

    let bytes = resp
        .body
        .collect()
        .await
        .map_err(|e| AppError::Internal(format!("read {key} body: {e}")))?
        .into_bytes();

    let s = String::from_utf8(bytes.to_vec())
        .map_err(|e| AppError::Internal(format!("{key} not utf8: {e}")))?;
    // accept both "<hex>  filename\n" and bare "<hex>" — shasum / openssl
    // each emit slightly different shapes.
    Ok(s.split_whitespace().next().unwrap_or("").to_lowercase())
}

async fn download_to(
    s3: &aws_sdk_s3::Client,
    bucket: &str,
    key: &str,
    dst: &Path,
) -> Result<(), AppError> {
    let resp = s3
        .get_object()
        .bucket(bucket)
        .key(key)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("get s3://{bucket}/{key}: {e}")))?;

    let mut file = tokio::fs::File::create(dst)
        .await
        .map_err(|e| AppError::Internal(format!("create {dst:?}: {e}")))?;

    // chunked stream so the 600mb whisper file never lands fully in
    // memory at once. `ByteStream::next` is an inherent async method;
    // no Stream trait import needed.
    let mut body = resp.body;
    loop {
        match body.next().await {
            Some(Ok(chunk)) => {
                file.write_all(&chunk)
                    .await
                    .map_err(|e| AppError::Internal(format!("write {dst:?}: {e}")))?;
            }
            Some(Err(e)) => {
                return Err(AppError::Internal(format!(
                    "stream s3://{bucket}/{key}: {e}"
                )));
            }
            None => break,
        }
    }
    file.flush().await.ok();
    Ok(())
}

fn sha_of(path: &Path) -> std::io::Result<String> {
    use std::io::Read;
    let mut f = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}
