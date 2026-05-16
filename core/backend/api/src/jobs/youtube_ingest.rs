//! youtube_ingest job: pull a youtube url through yt-dlp + ffmpeg, save
//! raw + video-only + two audio variants to the sf-voice internal bucket,
//! record the keys back onto the `documents` table.

use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use aws_sdk_s3::primitives::ByteStream;
use sea_orm::{ActiveModelTrait, ActiveValue::Set, EntityTrait, TransactionTrait};
use serde::Deserialize;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use uuid::Uuid;

use crate::{
    error::AppError,
    internal_bucket::{self, InternalBucket},
    jobs::append_step,
    models::StepStatus,
    state::AppState,
};

#[derive(Debug, Deserialize)]
struct Payload {
    document_id: String,
    source_url: String,
}

struct Meta {
    title: Option<String>,
    duration_seconds: Option<i64>,
}

pub async fn run(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    payload: Option<serde_json::Value>,
) -> Result<(), AppError> {
    let p: Payload = serde_json::from_value(
        payload.ok_or_else(|| AppError::Internal("youtube_ingest: empty payload".into()))?,
    )
    .map_err(|e| AppError::Internal(format!("youtube_ingest: bad payload: {e}")))?;

    let document_id = Uuid::parse_str(&p.document_id)
        .map_err(|e| AppError::Internal(format!("youtube_ingest: document_id parse: {e}")))?;

    // work_dir keyed by document_id (not job_id) so retries resume from
    // the previous attempt's intermediate files. cleaned up only on
    // success — failure leaves it for the next retry to skip the
    // already-completed steps.
    let work_dir = std::env::temp_dir().join(format!("sf-voice-yt-{document_id}"));
    std::fs::create_dir_all(&work_dir)
        .map_err(|e| AppError::Internal(format!("create work dir: {e}")))?;

    let result = run_steps(state, job_id, org_id, document_id, &p.source_url, &work_dir).await;

    // cleanup work_dir only on success — failure keeps the intermediate
    // files so the next retry can resume. log loudly either way so the
    // operator can confirm local disk isn't filling up.
    if result.is_ok() {
        match std::fs::remove_dir_all(&work_dir) {
            Ok(()) => tracing::info!(
                %document_id,
                work_dir = %work_dir.display(),
                "cleaned up local work_dir after successful ingest"
            ),
            Err(e) => tracing::warn!(
                %document_id,
                work_dir = %work_dir.display(),
                error = %e,
                "failed to clean up work_dir — manual cleanup may be needed"
            ),
        }
    } else {
        tracing::info!(
            %document_id,
            work_dir = %work_dir.display(),
            "leaving work_dir in place for retry — clean up after success or manually"
        );
    }

    if let Err(e) = &result {
        // emit a terminal "job failed" step so the timeline ui shows
        // where the flow died — the last `running` entry above it is
        // the step that actually broke. detail carries the error.
        let _ = append_step(
            state,
            org_id,
            job_id,
            "job failed",
            StepStatus::Failed,
            Some(e.to_string()),
        )
        .await;

        // emit a structured log before the state transition so we have
        // a record even if the UPDATE below itself fails (e.g. mysql
        // disconnect). this is the canonical "document went to failed"
        // signal — search logs for `document_failed` to find it.
        tracing::error!(
            event = "document_failed",
            %document_id,
            %job_id,
            %org_id,
            error = %e,
            "marking document processing_status=failed"
        );

        match (entities::documents::ActiveModel {
            id: Set(document_id.as_bytes().to_vec()),
            processing_status: Set("failed".into()),
            processing_error: Set(Some(e.to_string())),
            ..Default::default()
        }
        .update(&state.orm)
        .await)
        {
            Ok(_) => {
                tracing::info!(
                    %document_id,
                    "document processing_status=failed persisted"
                );
            }
            Err(db_err) => {
                // failure-to-persist-failure: log loudly. timeline
                // shows the original error but documents.processing_status
                // may still read 'uploading' or whatever the last
                // running state was.
                tracing::error!(
                    %document_id,
                    %job_id,
                    db_error = %db_err,
                    "FAILED to persist processing_status=failed — document row stuck"
                );
            }
        }
    }

    result
}

async fn run_steps(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    document_id: Uuid,
    source_url: &str,
    work_dir: &Path,
) -> Result<(), AppError> {
    let document_id_bytes = document_id.as_bytes().to_vec();

    // step 1: metadata via `yt-dlp -J`.
    append_step(
        state,
        org_id,
        job_id,
        "fetching metadata",
        StepStatus::Running,
        None,
    )
    .await?;
    let meta = fetch_metadata(source_url).await?;
    append_step(
        state,
        org_id,
        job_id,
        "fetching metadata",
        StepStatus::Done,
        Some(format!(
            "{} ({}s)",
            meta.title.clone().unwrap_or_else(|| "(no title)".into()),
            meta.duration_seconds.unwrap_or(0)
        )),
    )
    .await?;

    // parent doc gets title + duration + status='downloading' early so
    // the row reflects partial progress even if a later step fails.
    entities::documents::ActiveModel {
        id: Set(document_id_bytes.clone()),
        title: Set(meta.title.clone()),
        duration_ms: Set(meta
            .duration_seconds
            .map(|s| i32::try_from(s.saturating_mul(1000)).unwrap_or(i32::MAX))),
        processing_status: Set("downloading".into()),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;

    // step 2: download merged mp4. skip yt-dlp if a prior attempt left
    // raw.mp4 on disk — retries reuse the existing file instead of
    // redownloading hundreds of MB.
    let raw_path = work_dir.join("raw.mp4");
    if file_nonempty(&raw_path) {
        append_step(
            state,
            org_id,
            job_id,
            "downloading media",
            StepStatus::Done,
            Some("skipped — already on disk".into()),
        )
        .await?;
    } else {
        append_step(
            state,
            org_id,
            job_id,
            "downloading media",
            StepStatus::Running,
            None,
        )
        .await?;
        run_yt_dlp_download(state, org_id, job_id, source_url, &raw_path).await?;
        append_step(
            state,
            org_id,
            job_id,
            "downloading media",
            StepStatus::Done,
            None,
        )
        .await?;
    }

    // step 3: extract audio variants (m4a re-encode aac for container
    // compatibility; wav pcm_s16le keeps source sample rate + channels).
    entities::documents::ActiveModel {
        id: Set(document_id_bytes.clone()),
        processing_status: Set("extracting".into()),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;
    let m4a_path = work_dir.join("audio.m4a");
    let wav_path = work_dir.join("audio.wav");
    if file_nonempty(&m4a_path) && file_nonempty(&wav_path) {
        append_step(
            state,
            org_id,
            job_id,
            "extracting audio",
            StepStatus::Done,
            Some("skipped — already on disk".into()),
        )
        .await?;
    } else {
        append_step(
            state,
            org_id,
            job_id,
            "extracting audio",
            StepStatus::Running,
            None,
        )
        .await?;
        if !file_nonempty(&m4a_path) {
            ffmpeg_extract_audio_aac(&raw_path, &m4a_path).await?;
        }
        if !file_nonempty(&wav_path) {
            ffmpeg_extract_audio_wav(&raw_path, &wav_path).await?;
        }
        append_step(
            state,
            org_id,
            job_id,
            "extracting audio",
            StepStatus::Done,
            None,
        )
        .await?;
    }

    // step 4: extract video-only with stream copy. fast, no re-encode.
    let video_path = work_dir.join("video.mp4");
    if file_nonempty(&video_path) {
        append_step(
            state,
            org_id,
            job_id,
            "extracting video",
            StepStatus::Done,
            Some("skipped — already on disk".into()),
        )
        .await?;
    } else {
        append_step(
            state,
            org_id,
            job_id,
            "extracting video",
            StepStatus::Running,
            None,
        )
        .await?;
        ffmpeg_extract_video_copy(&raw_path, &video_path).await?;
        append_step(
            state,
            org_id,
            job_id,
            "extracting video",
            StepStatus::Done,
            None,
        )
        .await?;
    }

    // step 5: upload all four to s3.
    entities::documents::ActiveModel {
        id: Set(document_id_bytes.clone()),
        processing_status: Set("uploading".into()),
        ..Default::default()
    }
    .update(&state.orm)
    .await?;
    let bucket = internal_bucket::open().await?;
    let key_prefix = format!("{}/youtube/{}", bucket.prefix, document_id);
    let raw_key = format!("{key_prefix}/raw.mp4");
    let video_key = format!("{key_prefix}/video.mp4");
    let m4a_key = format!("{key_prefix}/audio.m4a");
    let wav_key = format!("{key_prefix}/audio.wav");

    // one step event per file so the timeline shows which upload is
    // running. wrapped in upload_with_retry so transient s3 errors
    // (5xx, throttling, io reset) don't fail the whole job.
    let uploads: &[(&str, &Path, &str, &str)] = &[
        ("raw.mp4", &raw_path, &raw_key, "video/mp4"),
        ("video.mp4", &video_path, &video_key, "video/mp4"),
        ("audio.m4a", &m4a_path, &m4a_key, "audio/mp4"),
        ("audio.wav", &wav_path, &wav_key, "audio/wav"),
    ];
    for (name, path, key, mime) in uploads {
        let step_label = format!("uploading {name}");
        let size_mb = std::fs::metadata(path)
            .ok()
            .map(|m| format!("{:.1} MB", m.len() as f64 / 1_048_576.0))
            .unwrap_or_else(|| "?".into());

        // skip the upload if the object is already in s3 from a prior
        // attempt. saves a multi-minute round-trip on retry of a large
        // raw.mp4 / video.mp4.
        if object_exists(&bucket, key).await {
            append_step(
                state,
                org_id,
                job_id,
                &step_label,
                StepStatus::Done,
                Some(format!("{size_mb} — skipped, already on s3")),
            )
            .await?;
            continue;
        }

        append_step(
            state,
            org_id,
            job_id,
            &step_label,
            StepStatus::Running,
            Some(size_mb.clone()),
        )
        .await?;
        upload_with_retry(&bucket, key, path, mime, 3).await?;
        append_step(
            state,
            org_id,
            job_id,
            &step_label,
            StepStatus::Done,
            Some(size_mb),
        )
        .await?;
    }

    let bucket_name = &bucket.bucket;
    tracing::info!(
        %document_id,
        raw  = %format!("s3://{bucket_name}/{raw_key}"),
        video = %format!("s3://{bucket_name}/{video_key}"),
        m4a  = %format!("s3://{bucket_name}/{m4a_key}"),
        wav  = %format!("s3://{bucket_name}/{wav_key}"),
        "youtube_ingest: s3 uploads complete"
    );

    // step 6: finalize parent doc + insert derived docs in one tx so
    // a partial commit can't leave the tree half-built.
    let txn = state.orm.begin().await?;

    // parent doc gets the raw.mp4 details + flips to ready.
    entities::documents::ActiveModel {
        id: Set(document_id_bytes.clone()),
        bucket: Set(Some(bucket.bucket.clone())),
        s3_key: Set(Some(raw_key)),
        filename: Set(Some("raw.mp4".into())),
        mime_type: Set(Some("video/mp4".into())),
        processing_status: Set("ready".into()),
        processing_error: Set(None),
        ..Default::default()
    }
    .update(&txn)
    .await?;

    // 3 derived docs — one per extracted asset. they share the parent's
    // title for display, point at the parent via source_id, and are
    // born 'ready' since the file is already on s3. we capture the
    // wav child's id so we can enqueue transcription after commit.
    let derived: [(&str, String, &str, &str); 3] = [
        ("video", video_key, "video.mp4", "video/mp4"),
        ("audio", m4a_key, "audio.m4a", "audio/mp4"),
        ("audio", wav_key, "audio.wav", "audio/wav"),
    ];
    let mut wav_child_id: Option<Uuid> = None;
    for (kind, s3_key, filename, mime) in derived {
        let child_id = Uuid::now_v7();
        if filename == "audio.wav" {
            wav_child_id = Some(child_id);
        }
        entities::documents::ActiveModel {
            id: Set(child_id.as_bytes().to_vec()),
            r#type: Set("internal".into()),
            media_kind: Set(kind.into()),
            source_kind: Set("youtube".into()),
            source_id: Set(Some(document_id_bytes.clone())),
            bucket: Set(Some(bucket.bucket.clone())),
            s3_key: Set(Some(s3_key)),
            filename: Set(Some(filename.into())),
            mime_type: Set(Some(mime.into())),
            processing_status: Set("ready".into()),
            title: Set(meta.title.clone()),
            ..Default::default()
        }
        .insert(&txn)
        .await?;
    }

    txn.commit().await?;

    // enqueue transcription against the wav child. independent job +
    // re-runnable per the design — failure here doesn't fail ingest.
    if let Some(wav_id) = wav_child_id {
        let t_job = Uuid::now_v7();
        let payload = serde_json::json!({ "document_id": wav_id.to_string() });
        let row = entities::jobs::ActiveModel {
            id: Set(t_job.as_bytes().to_vec()),
            org_id: Set(org_id.as_bytes().to_vec()),
            kind: Set("transcribe_document".into()),
            subject_type: Set("document".into()),
            subject_id: Set(Some(wav_id.as_bytes().to_vec())),
            status: Set("queued".into()),
            payload: Set(Some(payload)),
            ..Default::default()
        };
        if let Err(e) = row.insert(&state.orm).await {
            tracing::warn!(?e, %wav_id, "failed to enqueue transcribe_document — re-trigger manually");
        }
    }

    append_step(state, org_id, job_id, "ready", StepStatus::Done, None).await?;
    Ok(())
}

async fn fetch_metadata(url: &str) -> Result<Meta, AppError> {
    let out = Command::new("yt-dlp")
        .args(["-J", "--no-warnings", "--no-playlist", url])
        .output()
        .await
        .map_err(|e| AppError::Internal(format!("yt-dlp spawn: {e}")))?;

    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(AppError::BadRequest(format!(
            "yt-dlp metadata failed: {}",
            stderr.lines().last().unwrap_or("")
        )));
    }

    let v: serde_json::Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| AppError::Internal(format!("yt-dlp -J parse: {e}")))?;

    let title = v.get("title").and_then(|t| t.as_str()).map(str::to_string);
    let duration_seconds = v
        .get("duration")
        .and_then(|d| d.as_f64())
        .map(|f| f.round() as i64);

    Ok(Meta {
        title,
        duration_seconds,
    })
}

/// throttle between progress events written to progress_steps. yt-dlp
/// emits a [download] line for every fragment when on HLS — at ~5s/frag
/// that's already coarse, but a 30-min video would otherwise be ~360
/// rows. 2 seconds is the eyeball-it-feels-live number.
const PROGRESS_THROTTLE: Duration = Duration::from_secs(2);

async fn run_yt_dlp_download(
    state: &AppState,
    org_id: Uuid,
    job_id: Uuid,
    url: &str,
    out_path: &Path,
) -> Result<(), AppError> {
    let mut child = Command::new("yt-dlp")
        .args([
            "-f",
            "bv*+ba/best",
            "--merge-output-format",
            "mp4",
            "--no-warnings",
            "--no-playlist",
            "--newline",
            "-o",
            path_str(out_path)?,
            url,
        ])
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::Internal(format!("yt-dlp download spawn: {e}")))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| AppError::Internal("yt-dlp stdout pipe missing".into()))?;
    let mut lines = BufReader::new(stdout).lines();

    let mut last_emit = std::time::Instant::now()
        .checked_sub(PROGRESS_THROTTLE)
        .unwrap_or_else(std::time::Instant::now);

    loop {
        let next = lines
            .next_line()
            .await
            .map_err(|e| AppError::Internal(format!("yt-dlp stdout read: {e}")))?;
        let Some(line) = next else { break };

        tracing::info!("yt-dlp: {line}");

        if let Some(detail) = parse_download_progress(&line) {
            if last_emit.elapsed() >= PROGRESS_THROTTLE {
                let _ = append_step(
                    state,
                    org_id,
                    job_id,
                    "downloading media",
                    StepStatus::Running,
                    Some(detail),
                )
                .await;
                last_emit = std::time::Instant::now();
            }
        }
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::Internal(format!("yt-dlp wait: {e}")))?;

    if !status.success() {
        return Err(AppError::BadRequest(format!("yt-dlp exited with {status}")));
    }
    Ok(())
}

fn parse_download_progress(line: &str) -> Option<String> {
    let trimmed = line.trim_start();
    let rest = trimmed.strip_prefix("[download]")?.trim_start();
    let first = rest.split_whitespace().next()?;
    if !first.ends_with('%') {
        return None;
    }
    Some(rest.to_string())
}

async fn ffmpeg_extract_audio_aac(src: &Path, dst: &Path) -> Result<(), AppError> {
    ffmpeg(&[
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        path_str(src)?,
        "-vn",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        path_str(dst)?,
    ])
    .await
}

async fn ffmpeg_extract_audio_wav(src: &Path, dst: &Path) -> Result<(), AppError> {
    ffmpeg(&[
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        path_str(src)?,
        "-vn",
        "-c:a",
        "pcm_s16le",
        path_str(dst)?,
    ])
    .await
}

async fn ffmpeg_extract_video_copy(src: &Path, dst: &Path) -> Result<(), AppError> {
    ffmpeg(&[
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        path_str(src)?,
        "-an",
        "-c:v",
        "copy",
        path_str(dst)?,
    ])
    .await
}

async fn ffmpeg(args: &[&str]) -> Result<(), AppError> {
    let status = Command::new("ffmpeg")
        .args(args)
        .status()
        .await
        .map_err(|e| AppError::Internal(format!("ffmpeg spawn: {e}")))?;
    if !status.success() {
        return Err(AppError::Internal(format!("ffmpeg exited with {status}")));
    }
    Ok(())
}

/// single-attempt upload — no retry, no error classification. used
/// directly only by upload_with_retry below.
async fn upload(
    bucket: &InternalBucket,
    key: &str,
    path: &Path,
    content_type: &str,
) -> Result<(), AppError> {
    let body = ByteStream::from_path(path)
        .await
        .map_err(|e| AppError::Internal(format!("bytestream from {path:?}: {e}")))?;

    let send = bucket
        .s3
        .put_object()
        .bucket(&bucket.bucket)
        .key(key)
        .content_type(content_type)
        .body(body)
        .send();

    let result = tokio::time::timeout(Duration::from_secs(600), send)
        .await
        .map_err(|_| AppError::Internal(format!("s3 put_object timed out: {key}")))?;

    if let Err(sdk_err) = result {
        // pull the real error out of the aws sdk wrapper. without this
        // we get "service error" from the default Display impl — useless
        // for debugging. service errors expose .code() + .message();
        // other errors (timeout, dispatch failure) stringify usefully.
        let detail = match &sdk_err {
            aws_sdk_s3::error::SdkError::ServiceError(se) => {
                let err = se.err();
                let code = err.meta().code().unwrap_or("UnknownCode");
                let msg = err.meta().message().unwrap_or("(no message)");
                format!("{code}: {msg}")
            }
            other => other.to_string(),
        };
        return Err(AppError::Internal(format!("s3 put_object {key}: {detail}")));
    }
    Ok(())
}

/// upload with bounded exponential backoff on transient errors. retries
/// only on classifiers below (5xx, throttling, IO/connect). 4xx errors
/// (auth, perm, bad-request) fail fast since retrying won't help.
async fn upload_with_retry(
    bucket: &InternalBucket,
    key: &str,
    path: &Path,
    content_type: &str,
    max_attempts: u32,
) -> Result<(), AppError> {
    let mut attempt: u32 = 0;
    loop {
        attempt += 1;
        match upload(bucket, key, path, content_type).await {
            Ok(()) => return Ok(()),
            Err(e) if attempt < max_attempts && is_retryable(&e) => {
                // 2^(attempt-1) seconds: 1s, 2s, 4s for max_attempts=3.
                let delay = Duration::from_secs(1u64 << (attempt - 1));
                tracing::warn!(
                    key,
                    attempt,
                    max_attempts,
                    backoff_secs = delay.as_secs(),
                    error = %e,
                    "s3 upload failed — retrying"
                );
                tokio::time::sleep(delay).await;
                continue;
            }
            Err(e) => return Err(e),
        }
    }
}

/// classify whether the error string looks like a transient s3 problem
/// we should retry. since the only error type we have at this point is
/// AppError::Internal(String), substring-match the canonical aws codes
/// + transport-level keywords. would be nicer with a typed error chain
/// but the existing upload() already collapses everything to a string.
fn is_retryable(err: &AppError) -> bool {
    let s = err.to_string();
    let needles = [
        "timed out",
        "RequestTimeout",
        "SlowDown",
        "ThrottlingException",
        "Throttling",
        "InternalError",
        "ServiceUnavailable",
        "503",
        "500",
        "502",
        "504",
        "broken pipe",
        "connection reset",
        "Connection reset",
        "dispatch failure",
    ];
    needles.iter().any(|n| s.contains(n))
}

fn path_str(p: &Path) -> Result<&str, AppError> {
    p.to_str()
        .ok_or_else(|| AppError::Internal(format!("non-utf8 path: {p:?}")))
}

/// true when the file exists and has a non-zero size. used to detect
/// "already done" intermediate outputs so retries can skip the step.
/// zero-byte files are treated as missing — they're the typical shape
/// of a tool that started writing then died.
fn file_nonempty(p: &Path) -> bool {
    std::fs::metadata(p).map(|m| m.len() > 0).unwrap_or(false)
}

/// head_object probe used to detect "already uploaded" on retry. any
/// error (including NotFound and IAM failures) returns false so the
/// upload step runs and surfaces the real reason if it's not just a
/// missing object.
async fn object_exists(bucket: &InternalBucket, key: &str) -> bool {
    bucket
        .s3
        .head_object()
        .bucket(&bucket.bucket)
        .key(key)
        .send()
        .await
        .is_ok()
}
