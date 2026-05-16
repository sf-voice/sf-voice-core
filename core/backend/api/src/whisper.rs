//! local whisper transcription via whisper-rs (FFI to whisper.cpp).
//!
//! one `WhisperContext` is loaded at startup from the ggml model file
//! resolved by `ai_models::bootstrap()` and shared via an Arc on
//! AppState. transcribe() is sync (whisper inference is cpu-bound),
//! so callers wrap it in `tokio::task::spawn_blocking` to keep the
//! async runtime free.

use std::path::Path;

use whisper_rs::{
    FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters,
};

use crate::error::AppError;

/// transcript segment with millisecond timing. timestamps come from
/// whisper's 10ms-resolution token alignment, scaled up.
#[derive(Debug, Clone)]
pub struct Segment {
    pub start_ms: i32,
    pub end_ms: i32,
    pub text: String,
}

/// segment after diarization alignment — adds a speaker label
/// (`speaker_0`, `speaker_1`, …) chosen by largest temporal overlap
/// with a `SpeakerTurn` from `crate::diarize`.
#[derive(Debug, Clone)]
pub struct LabeledSegment {
    pub start_ms: i32,
    pub end_ms: i32,
    pub text: String,
    pub speaker_label: String,
}

pub struct Whisper {
    ctx: WhisperContext,
}

// safety: WhisperContext wraps a whisper.cpp pointer that is read-only
// after construction (state is a separate per-call object). the
// underlying c++ context supports concurrent state creation, which is
// the only thing we do across threads.
unsafe impl Send for Whisper {}
unsafe impl Sync for Whisper {}

impl Whisper {
    /// load the ggml model. expensive — call once at startup.
    pub fn load(model_path: &Path) -> Result<Self, AppError> {
        let path_str = model_path
            .to_str()
            .ok_or_else(|| AppError::Internal(format!("non-utf8 model path: {model_path:?}")))?;
        let ctx = WhisperContext::new_with_params(path_str, WhisperContextParameters::default())
            .map_err(|e| AppError::Internal(format!("whisper load {path_str}: {e}")))?;
        tracing::info!(model = %path_str, "whisper model loaded");
        Ok(Self { ctx })
    }

    /// transcribe a mono 16khz f32 pcm buffer. blocking — caller wraps
    /// in spawn_blocking. language is auto-detected.
    pub fn transcribe(&self, pcm_f32_16k: &[f32]) -> Result<Vec<Segment>, AppError> {
        let mut state = self
            .ctx
            .create_state()
            .map_err(|e| AppError::Internal(format!("whisper state: {e}")))?;

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        let n_threads = std::thread::available_parallelism()
            .map(|n| n.get() as i32)
            .unwrap_or(4);
        params.set_n_threads(n_threads);
        params.set_translate(false);
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);

        state
            .full(params, pcm_f32_16k)
            .map_err(|e| AppError::Internal(format!("whisper full: {e}")))?;

        // whisper-rs 0.16 exposes a typed `WhisperSegment` via
        // `get_segment(i)`; timestamps are in centiseconds (10ms units),
        // text via `to_str()` borrows from the state buffer.
        let n = state.full_n_segments();
        let mut out = Vec::with_capacity(n as usize);
        for i in 0..n {
            let seg = state
                .get_segment(i)
                .ok_or_else(|| AppError::Internal(format!("whisper segment {i} oob")))?;
            let text = seg
                .to_str()
                .map_err(|e| AppError::Internal(format!("whisper segment {i} text: {e}")))?
                .trim()
                .to_string();
            out.push(Segment {
                start_ms: (seg.start_timestamp() * 10) as i32,
                end_ms: (seg.end_timestamp() * 10) as i32,
                text,
            });
        }
        Ok(out)
    }
}

/// align whisper segments with diarization turns. each segment gets
/// the speaker_id whose turn has the largest temporal overlap with
/// it; if no turn overlaps, falls back to `speaker_unknown`.
pub fn align_speakers(
    segments: Vec<Segment>,
    turns: &[crate::diarize::SpeakerTurn],
) -> Vec<LabeledSegment> {
    segments
        .into_iter()
        .map(|seg| {
            let label = best_speaker(seg.start_ms, seg.end_ms, turns)
                .map(|id| format!("speaker_{id}"))
                .unwrap_or_else(|| "speaker_unknown".to_string());
            LabeledSegment {
                start_ms: seg.start_ms,
                end_ms: seg.end_ms,
                text: seg.text,
                speaker_label: label,
            }
        })
        .collect()
}

fn best_speaker(seg_start: i32, seg_end: i32, turns: &[crate::diarize::SpeakerTurn]) -> Option<i32> {
    let mut best_overlap = 0i32;
    let mut best_id: Option<i32> = None;
    for t in turns {
        let overlap = (seg_end.min(t.end_ms) - seg_start.max(t.start_ms)).max(0);
        if overlap > best_overlap {
            best_overlap = overlap;
            best_id = Some(t.speaker_id);
        }
    }
    best_id
}
