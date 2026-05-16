//! OpenAI clients: Whisper (audio transcription) + embeddings.
//! one shared reqwest::Client lives on AppState; this module just
//! shapes the requests.
//!
//! both endpoints expect `OPENAI_API_KEY` in env. functions return
//! AppError::BadRequest when the key is missing so failure surfaces
//! to the customer's reasoning-path panel instead of a 500.

use std::time::Duration;

use reqwest::{multipart, Client};
use serde::{Deserialize, Serialize};

use crate::error::AppError;

const WHISPER_URL: &str = "https://api.openai.com/v1/audio/transcriptions";
const EMBEDDINGS_URL: &str = "https://api.openai.com/v1/embeddings";

pub const WHISPER_MODEL: &str = "whisper-1";
pub const EMBED_MODEL: &str = "text-embedding-3-small";
pub const EMBED_DIM: usize = 1536;

fn api_key() -> Result<String, AppError> {
    std::env::var("OPENAI_API_KEY").map_err(|_| {
        AppError::BadRequest(
            "OPENAI_API_KEY not set on the backend — add it to .env and restart.".into(),
        )
    })
}

// ─────────────────────────────────────────────────────────────────────
// Whisper — POST /v1/audio/transcriptions
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct WhisperResponse {
    pub text: String,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub duration: Option<f64>,
    #[serde(default)]
    pub segments: Vec<WhisperSegment>,
}

#[derive(Debug, Deserialize)]
pub struct WhisperSegment {
    pub id: i64,
    pub start: f64, // seconds
    pub end: f64,
    pub text: String,
    #[serde(default)]
    pub avg_logprob: Option<f64>,
}

/// upload an audio buffer + filename and return verbose_json segments.
/// caller is responsible for sourcing the bytes (we download from S3
/// in the transcribe job and feed the bytes here).
pub async fn transcribe_audio(
    http: &Client,
    filename: &str,
    bytes: Vec<u8>,
) -> Result<WhisperResponse, AppError> {
    let key = api_key()?;
    let part = multipart::Part::bytes(bytes)
        .file_name(filename.to_string())
        .mime_str("application/octet-stream")
        .map_err(|e| AppError::Internal(format!("multipart: {e}")))?;
    let form = multipart::Form::new()
        .text("model", WHISPER_MODEL)
        .text("response_format", "verbose_json")
        // include word-level + segment-level timing so we can spread
        // utterances on the timeline accurately.
        .text("timestamp_granularities[]", "segment")
        .part("file", part);

    let res = http
        .post(WHISPER_URL)
        .bearer_auth(&key)
        .timeout(Duration::from_secs(300))
        .multipart(form)
        .send()
        .await?;
    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_default();
        return Err(AppError::BadRequest(format!(
            "whisper {} — {}",
            status, text
        )));
    }
    let parsed: WhisperResponse = res.json().await?;
    Ok(parsed)
}

// ─────────────────────────────────────────────────────────────────────
// Embeddings — POST /v1/embeddings
// ─────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct EmbedRequest<'a> {
    model: &'a str,
    input: Vec<&'a str>,
}

#[derive(Debug, Deserialize)]
struct EmbedResponse {
    data: Vec<EmbedDatum>,
}

#[derive(Debug, Deserialize)]
struct EmbedDatum {
    embedding: Vec<f32>,
}

/// batch-embed a list of strings. OpenAI accepts up to 2048 inputs per
/// call; we cap at 100 to keep payloads manageable and re-batch if
/// callers send more.
pub async fn embed_texts(http: &Client, texts: &[&str]) -> Result<Vec<Vec<f32>>, AppError> {
    if texts.is_empty() {
        return Ok(vec![]);
    }
    let key = api_key()?;
    let mut out: Vec<Vec<f32>> = Vec::with_capacity(texts.len());
    for chunk in texts.chunks(100) {
        let body = EmbedRequest {
            model: EMBED_MODEL,
            input: chunk.to_vec(),
        };
        let res = http
            .post(EMBEDDINGS_URL)
            .bearer_auth(&key)
            .timeout(Duration::from_secs(60))
            .json(&body)
            .send()
            .await?;
        if !res.status().is_success() {
            let status = res.status();
            let text = res.text().await.unwrap_or_default();
            return Err(AppError::BadRequest(format!(
                "embeddings {} — {}",
                status, text
            )));
        }
        let parsed: EmbedResponse = res.json().await?;
        for d in parsed.data {
            if d.embedding.len() != EMBED_DIM {
                return Err(AppError::Internal(format!(
                    "expected {} dims, got {}",
                    EMBED_DIM,
                    d.embedding.len()
                )));
            }
            out.push(d.embedding);
        }
    }
    Ok(out)
}
