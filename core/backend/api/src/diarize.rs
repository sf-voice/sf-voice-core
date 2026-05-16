//! local speaker diarization via sherpa-rs (onnxruntime under the
//! hood). pyannote 3.0 segmentation + 3d-speaker eres2netv2 embedding,
//! both as onnx models pulled by `ai_models::bootstrap()` from s3.
//!
//! one `Diarize` instance is loaded at startup and shared via an Arc
//! on AppState. compute() is sync + cpu-bound — wrap callers in
//! `tokio::task::spawn_blocking`.

use std::path::Path;
use std::sync::Mutex;

use sherpa_rs::diarize::{Diarize, DiarizeConfig};

use crate::error::AppError;

/// diarization output: contiguous span where one speaker held the
/// floor. `speaker_id` is sherpa's cluster id (0, 1, 2…) — meaningful
/// only within a single audio file.
#[derive(Debug, Clone)]
pub struct SpeakerTurn {
    pub start_ms: i32,
    pub end_ms: i32,
    pub speaker_id: i32,
}

/// thin wrapper around sherpa-rs's diarizer. internally holds a
/// `Mutex` because sherpa's `Diarize::compute` takes `&mut self` —
/// concurrent jobs serialise here. fine for v1: the job runner is a
/// single in-process worker.
pub struct Diarizer {
    inner: Mutex<Diarize>,
}

impl Diarizer {
    /// load both onnx models. expensive — call once at startup.
    pub fn load(segmentation: &Path, embedding: &Path) -> Result<Self, AppError> {
        let seg = segmentation
            .to_str()
            .ok_or_else(|| AppError::Internal("non-utf8 segmentation path".into()))?;
        let emb = embedding
            .to_str()
            .ok_or_else(|| AppError::Internal("non-utf8 embedding path".into()))?;

        // num_clusters=None → auto-detect via clustering threshold.
        // sherpa's default threshold (~0.5) works for typical 2-5
        // speaker corpora; tune later if recall on long monologues
        // produces phantom speakers.
        let cfg = DiarizeConfig {
            num_clusters: None,
            ..Default::default()
        };

        let d = Diarize::new(seg, emb, cfg)
            .map_err(|e| AppError::Internal(format!("sherpa diarize load: {e}")))?;
        tracing::info!(seg = %seg, emb = %emb, "diarization models loaded");
        Ok(Self {
            inner: Mutex::new(d),
        })
    }

    /// run diarization over a mono 16khz f32 pcm buffer. returns
    /// speaker turns in source order. blocking — caller wraps in
    /// spawn_blocking.
    pub fn diarize(&self, pcm_f32_16k: Vec<f32>) -> Result<Vec<SpeakerTurn>, AppError> {
        let mut guard = self
            .inner
            .lock()
            .map_err(|_| AppError::Internal("diarizer mutex poisoned".into()))?;
        let segs = guard
            .compute(pcm_f32_16k, None)
            .map_err(|e| AppError::Internal(format!("sherpa compute: {e}")))?;
        Ok(segs
            .into_iter()
            .map(|s| SpeakerTurn {
                // sherpa segment.start / .end are seconds (f32).
                start_ms: (s.start * 1000.0) as i32,
                end_ms: (s.end * 1000.0) as i32,
                speaker_id: s.speaker,
            })
            .collect())
    }
}
