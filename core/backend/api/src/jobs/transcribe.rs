//! transcribe job: pull a call's audio from S3 → Whisper → per-segment
//! `transcripts` rows → batched OpenAI embeddings → duckdb. emits step
//! events so the reasoning-path drawer can render progress live.
//!
//! re-transcribe semantics: delete-then-insert. the `jobs` table
//! already tracks who/when/why, so a per-run grouping table is
//! redundant — only the canonical (latest) transcript exists.

use duckdb::params;
use sea_orm::{
    ActiveModelTrait,
    ActiveValue::{NotSet, Set},
    ColumnTrait, ConnectionTrait, DatabaseConnection, EntityTrait, QueryFilter, QueryOrder,
};
use uuid::Uuid;

use crate::{
    aws_creds,
    error::AppError,
    jobs::append_step,
    models::StepStatus,
    openai::{self, EMBED_MODEL, WHISPER_MODEL},
    state::AppState,
};

pub async fn run(
    state: &AppState,
    job_id: Uuid,
    org_id: Uuid,
    payload: Option<serde_json::Value>,
) -> Result<(), AppError> {
    let call_id = payload
        .as_ref()
        .and_then(|p| p.get("call_id"))
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(|| AppError::Internal("transcribe job missing call_id in payload".into()))?;

    // re-runs: wipe prior transcripts for this call so we land in a
    // clean canonical state. the `jobs` row for this attempt is the
    // audit record.
    entities::transcripts::Entity::delete_many()
        .filter(entities::transcripts::Column::CallId.eq(call_id.as_bytes().to_vec()))
        .exec(&state.orm)
        .await?;

    // fetch the audio URI from the call row.
    let call = entities::calls::Entity::find_by_id(call_id.as_bytes().to_vec())
        .filter(entities::calls::Column::OrgId.eq(org_id.as_bytes().to_vec()))
        .one(&state.orm)
        .await?;
    let audio_uri = call
        .and_then(|c| c.audio_uri)
        .ok_or_else(|| AppError::Internal("call has no audio_uri".into()))?;
    let (bucket_name, key) = parse_s3_uri(&audio_uri).ok_or_else(|| {
        AppError::BadRequest(format!(
            "audio_uri not in s3://bucket/key form: {audio_uri}"
        ))
    })?;

    // 3. download the audio.
    append_step(
        state,
        org_id,
        job_id,
        "downloading audio",
        StepStatus::Running,
        None,
    )
    .await?;
    let bucket = aws_creds::open_for_org(&state.orm, org_id).await?;
    let bytes = bucket
        .s3
        .get_object()
        .bucket(&bucket_name)
        .key(&key)
        .send()
        .await
        .map_err(|e| AppError::BadRequest(format!("S3 GetObject: {e}")))?
        .body
        .collect()
        .await
        .map_err(|e| AppError::Internal(format!("S3 body stream: {e}")))?
        .into_bytes()
        .to_vec();
    append_step(
        state,
        org_id,
        job_id,
        "downloading audio",
        StepStatus::Done,
        Some(format!("{:.1} MB", bytes.len() as f64 / 1_048_576.0)),
    )
    .await?;

    // 4. whisper.
    append_step(
        state,
        org_id,
        job_id,
        "transcribing with whisper",
        StepStatus::Running,
        None,
    )
    .await?;
    let filename = key.rsplit('/').next().unwrap_or("audio").to_string();
    let resp = openai::transcribe_audio(&state.http, &filename, bytes).await?;
    let segments = resp.segments;
    if segments.is_empty() {
        // whisper occasionally returns 0 segments on short / empty audio.
        // still write a single transcript with the full text so the ui
        // shows something.
        let full = resp.text.trim();
        if !full.is_empty() {
            insert_segment(
                &state.orm,
                call_id,
                0,
                (resp.duration.unwrap_or(0.0) * 1000.0) as i32,
                full,
                None,
            )
            .await?;
        }
    } else {
        for seg in &segments {
            insert_segment(
                &state.orm,
                call_id,
                (seg.start * 1000.0) as i32,
                (seg.end * 1000.0) as i32,
                seg.text.trim(),
                seg.avg_logprob.map(|p| (p as f32).exp()),
            )
            .await?;
        }
    }
    append_step(
        state,
        org_id,
        job_id,
        "transcribing with whisper",
        StepStatus::Done,
        Some(format!(
            "{} segments · {:.1}s",
            segments.len(),
            resp.duration.unwrap_or(0.0)
        )),
    )
    .await?;

    // 5. duration on the call row.
    if let Some(d) = resp.duration {
        entities::calls::ActiveModel {
            id: Set(call_id.as_bytes().to_vec()),
            duration_ms: Set(Some((d * 1000.0) as i32)),
            ..Default::default()
        }
        .update(&state.orm)
        .await?;
    }

    // 6. embeddings → duckdb. failure here is recoverable — surface as a
    // warning step but don't fail the whole run.
    append_step(
        state,
        org_id,
        job_id,
        "embedding utterances",
        StepStatus::Running,
        None,
    )
    .await?;
    match embed_and_store(state, org_id, call_id, job_id).await {
        Ok(n) => {
            append_step(
                state,
                org_id,
                job_id,
                "embedding utterances",
                StepStatus::Done,
                Some(format!("{n} vectors stored")),
            )
            .await?;
        }
        Err(e) => {
            tracing::warn!(?e, "embeddings failed — transcripts still ok");
            append_step(
                state,
                org_id,
                job_id,
                "embedding utterances",
                StepStatus::Failed,
                Some(format!("{e}")),
            )
            .await?;
        }
    }

    Ok(())
}

fn parse_s3_uri(uri: &str) -> Option<(String, String)> {
    let rest = uri.strip_prefix("s3://")?;
    let mut split = rest.splitn(2, '/');
    let bucket = split.next()?.to_string();
    let key = split.next()?.to_string();
    Some((bucket, key))
}

async fn insert_segment<C: ConnectionTrait>(
    db: &C,
    call_id: Uuid,
    start_ms: i32,
    end_ms: i32,
    text: &str,
    confidence: Option<f32>,
) -> Result<(), AppError> {
    entities::transcripts::ActiveModel {
        id: NotSet,
        // polymorphic subject — call path always sets call_id only.
        call_id: Set(Some(call_id.as_bytes().to_vec())),
        speaker_label: Set("unknown".into()),
        start_ms: Set(start_ms),
        end_ms: Set(end_ms),
        text: Set(text.into()),
        confidence: Set(confidence),
        model_version: Set(format!("{WHISPER_MODEL}+v1")),
        ..Default::default()
    }
    .insert(db)
    .await?;
    Ok(())
}

async fn embed_and_store(
    state: &AppState,
    org_id: Uuid,
    call_id: Uuid,
    job_id: Uuid,
) -> Result<usize, AppError> {
    // re-fetch by call_id — re-runs already cleared prior rows above
    // so this returns just what we inserted in this job.
    let rows = entities::transcripts::Entity::find()
        .filter(entities::transcripts::Column::CallId.eq(call_id.as_bytes().to_vec()))
        .order_by_asc(entities::transcripts::Column::StartMs)
        .all(&state.orm)
        .await?;
    if rows.is_empty() {
        return Ok(0);
    }

    let texts: Vec<&str> = rows.iter().map(|r| r.text.as_str()).collect();
    let vectors = openai::embed_texts(&state.http, &texts).await?;
    if vectors.len() != rows.len() {
        return Err(AppError::Internal(format!(
            "embed count mismatch: {} vs {}",
            vectors.len(),
            rows.len()
        )));
    }

    // duckdb write — blocking, but fast for ~50 rows at a time. drop
    // the connection guard before .await'ing anything else.
    let conn = state.db.clone();
    let org_id_str = org_id.to_string();
    let call_id_str = call_id.to_string();
    let job_id_str = job_id.to_string();
    let inserted = tokio::task::spawn_blocking(move || -> Result<usize, AppError> {
        let c = conn.lock().map_err(|_| AppError::Poisoned)?;
        let tx = c.unchecked_transaction()?;
        // upsert: a re-transcribe with the same model overwrites the
        // embedding via DELETE + INSERT keyed on (transcript_id, model).
        let mut count = 0usize;
        for (row, vec) in rows.iter().zip(vectors.iter()) {
            tx.execute(
                "DELETE FROM transcript_embeddings WHERE transcript_id = ? AND model = ?",
                params![row.id, EMBED_MODEL],
            )?;
            // duckdb's rust binding doesn't impl ToSql for Vec<f32>, so we
            // format the FLOAT[1536] as a SQL array literal `[1.0, 2.0, …]`
            // and inline it. floats serialised via `{:e}` never contain
            // SQL-special chars, so there's no injection surface here.
            let mut embedding_literal = String::with_capacity(vec.len() * 12 + 2);
            embedding_literal.push('[');
            for (i, f) in vec.iter().enumerate() {
                if i > 0 {
                    embedding_literal.push(',');
                }
                use std::fmt::Write;
                write!(&mut embedding_literal, "{:e}", f)
                    .map_err(|e| AppError::Internal(format!("embedding fmt: {e}")))?;
            }
            embedding_literal.push(']');
            let sql = format!(
                r#"
                INSERT INTO transcript_embeddings
                    (transcript_id, call_id, org_id, run_id, model, embedding, text)
                VALUES (?, ?, ?, ?, ?, {embedding_literal}::FLOAT[1536], ?)
                "#,
            );
            tx.execute(
                &sql,
                params![
                    row.id,
                    call_id_str,
                    org_id_str,
                    job_id_str,
                    EMBED_MODEL,
                    row.text
                ],
            )?;
            count += 1;
        }
        tx.commit()?;
        Ok(count)
    })
    .await
    .map_err(|e| AppError::Internal(format!("spawn_blocking join: {e}")))??;

    // silence unused import warning when the path above doesn't reach it.
    let _: Option<&DatabaseConnection> = None;

    Ok(inserted)
}
