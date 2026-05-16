//! transcribe_document job: pull a document's audio.wav from the
//! internal s3 bucket → ffmpeg-resample to mono 16khz f32 → local
//! whisper + sherpa diarization → align speaker labels onto whisper
//! segments → DELETE + INSERT into `transcripts`.
//!
//! re-runs are delete-then-insert (same pattern as the call-side
//! transcribe job); the audit trail is the `jobs` row.

use std::path::Path;
use std::time::Duration;

use sea_orm::{
    ActiveModelTrait, ActiveValue::{NotSet, Set},
    ColumnTrait, EntityTrait, QueryFilter,
};
use serde::Deserialize;
use tokio::process::Command;
use uuid::Uuid;

use crate::{
    error::AppError,
    internal_bucket,
    jobs::append_step,
    models::StepStatus,
    state::AppState,
    whisper::align_speakers,
};

const WHISPER_MODEL_VERSION: &str = "ggml-large-v3-turbo-q5_0";

#[derive(Debug, Deserialize)]
struct Payload {
    document_id: String,
}

pub async fn run(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    payload: Option<serde_json::Value>,
) -> Result<(), AppError> {
    let p: Payload = serde_json::from_value(
        payload.ok_or_else(|| AppError::Internal("transcribe_document: empty payload".into()))?,
    )
    .map_err(|e| AppError::Internal(format!("transcribe_document: bad payload: {e}")))?;

    let document_id = Uuid::parse_str(&p.document_id)
        .map_err(|e| AppError::Internal(format!("transcribe_document: bad document_id: {e}")))?;
    let document_id_bytes = document_id.as_bytes().to_vec();

    // step 1: load doc + locate s3 object.
    let doc = entities::documents::Entity::find_by_id(document_id_bytes.clone())
        .one(&state.orm)
        .await?
        .ok_or_else(|| AppError::Internal(format!("document {document_id} not found")))?;

    let bucket_name = doc
        .bucket
        .clone()
        .ok_or_else(|| AppError::BadRequest("document has no s3 bucket".into()))?;
    let s3_key = doc
        .s3_key
        .clone()
        .ok_or_else(|| AppError::BadRequest("document has no s3 key".into()))?;

    // step 2: workdir + download. clean up regardless of outcome.
    let work_dir = std::env::temp_dir().join(format!("sf-voice-tx-{job_id}"));
    std::fs::create_dir_all(&work_dir)
        .map_err(|e| AppError::Internal(format!("create work dir: {e}")))?;

    let result = run_steps(
        state,
        job_id,
        org_id,
        document_id_bytes,
        &bucket_name,
        &s3_key,
        &work_dir,
    )
    .await;

    let _ = std::fs::remove_dir_all(&work_dir);
    result
}

async fn run_steps(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    document_id_bytes: Vec<u8>,
    bucket_name: &str,
    s3_key: &str,
    work_dir: &Path,
) -> Result<(), AppError> {
    // download.
    append_step(state, org_id, job_id, "downloading audio", StepStatus::Running, None).await?;
    let raw_path = work_dir.join("audio_raw.wav");
    let bucket = internal_bucket::open().await?;
    if bucket.bucket != bucket_name {
        return Err(AppError::BadRequest(format!(
            "document bucket {bucket_name} != internal bucket {}",
            bucket.bucket
        )));
    }
    let resp = bucket
        .s3
        .get_object()
        .bucket(bucket_name)
        .key(s3_key)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("s3 get {s3_key}: {e}")))?;
    let bytes = resp
        .body
        .collect()
        .await
        .map_err(|e| AppError::Internal(format!("s3 stream: {e}")))?
        .into_bytes();
    tokio::fs::write(&raw_path, &bytes)
        .await
        .map_err(|e| AppError::Internal(format!("write {raw_path:?}: {e}")))?;
    append_step(
        state,
        org_id,
        job_id,
        "downloading audio",
        StepStatus::Done,
        Some(format!("{:.1} MB", bytes.len() as f64 / 1_048_576.0)),
    )
    .await?;

    // resample to mono 16khz f32 — both whisper.cpp and sherpa's
    // pyannote/3d-speaker pipeline expect that exact shape.
    append_step(state, org_id, job_id, "resampling audio", StepStatus::Running, None).await?;
    let pcm_path = work_dir.join("audio_16k.wav");
    ffmpeg_to_16k_mono_f32(&raw_path, &pcm_path).await?;
    append_step(state, org_id, job_id, "resampling audio", StepStatus::Done, None).await?;

    // load samples once; pass to whisper + diarize.
    let pcm_path_str = pcm_path
        .to_str()
        .ok_or_else(|| AppError::Internal("non-utf8 pcm path".into()))?
        .to_string();
    let samples: Vec<f32> = tokio::task::spawn_blocking(move || -> Result<Vec<f32>, AppError> {
        let (samples, _rate) = sherpa_rs::read_audio_file(&pcm_path_str)
            .map_err(|e| AppError::Internal(format!("read {pcm_path_str}: {e}")))?;
        Ok(samples)
    })
    .await
    .map_err(|e| AppError::Internal(format!("read audio join: {e}")))??;

    // whisper transcription. cpu-bound → spawn_blocking.
    append_step(state, org_id, job_id, "transcribing", StepStatus::Running, None).await?;
    let whisper = state.whisper.clone();
    let whisper_samples = samples.clone();
    let segments = tokio::task::spawn_blocking(move || whisper.transcribe(&whisper_samples))
        .await
        .map_err(|e| AppError::Internal(format!("whisper join: {e}")))??;
    append_step(
        state,
        org_id,
        job_id,
        "transcribing",
        StepStatus::Done,
        Some(format!("{} segments", segments.len())),
    )
    .await?;

    // diarization. also cpu-bound + serialised inside a Mutex (the
    // job runner is single-worker so no contention in v1).
    append_step(state, org_id, job_id, "diarizing", StepStatus::Running, None).await?;
    let diarizer = state.diarizer.clone();
    let turns = tokio::task::spawn_blocking(move || diarizer.diarize(samples))
        .await
        .map_err(|e| AppError::Internal(format!("diarize join: {e}")))??;
    let n_speakers = turns
        .iter()
        .map(|t| t.speaker_id)
        .collect::<std::collections::BTreeSet<_>>()
        .len();
    append_step(
        state,
        org_id,
        job_id,
        "diarizing",
        StepStatus::Done,
        Some(format!("{n_speakers} speaker(s), {} turns", turns.len())),
    )
    .await?;

    let labeled = align_speakers(segments, &turns);

    // delete-then-insert. re-runs land in a clean canonical state.
    append_step(state, org_id, job_id, "writing transcripts", StepStatus::Running, None).await?;
    entities::transcripts::Entity::delete_many()
        .filter(entities::transcripts::Column::DocumentId.eq(document_id_bytes.clone()))
        .exec(&state.orm)
        .await?;

    let mut written = 0usize;
    for seg in &labeled {
        entities::transcripts::ActiveModel {
            id: NotSet,
            // polymorphic subject: documents-side sets document_id only.
            call_id: Set(None),
            document_id: Set(Some(document_id_bytes.clone())),
            speaker_label: Set(seg.speaker_label.clone()),
            start_ms: Set(seg.start_ms),
            end_ms: Set(seg.end_ms),
            text: Set(seg.text.clone()),
            confidence: Set(None),
            model_version: Set(format!("{WHISPER_MODEL_VERSION}+pyannote-3.0")),
            ..Default::default()
        }
        .insert(&state.orm)
        .await?;
        written += 1;
    }
    append_step(
        state,
        org_id,
        job_id,
        "writing transcripts",
        StepStatus::Done,
        Some(format!("{written} rows")),
    )
    .await?;

    Ok(())
}

async fn ffmpeg_to_16k_mono_f32(src: &Path, dst: &Path) -> Result<(), AppError> {
    let src_s = src
        .to_str()
        .ok_or_else(|| AppError::Internal("non-utf8 src path".into()))?;
    let dst_s = dst
        .to_str()
        .ok_or_else(|| AppError::Internal("non-utf8 dst path".into()))?;

    // -ac 1: mono. -ar 16000: 16khz. -c:a pcm_f32le: float wav so
    // sherpa_rs::read_audio_file returns Vec<f32> directly.
    let status = tokio::time::timeout(
        Duration::from_secs(600),
        Command::new("ffmpeg")
            .args([
                "-y", "-hide_banner", "-loglevel", "error", "-i", src_s, "-ac", "1", "-ar",
                "16000", "-c:a", "pcm_f32le", dst_s,
            ])
            .status(),
    )
    .await
    .map_err(|_| AppError::Internal("ffmpeg resample timed out".into()))?
    .map_err(|e| AppError::Internal(format!("ffmpeg spawn: {e}")))?;
    if !status.success() {
        return Err(AppError::Internal(format!("ffmpeg exited with {status}")));
    }
    Ok(())
}
