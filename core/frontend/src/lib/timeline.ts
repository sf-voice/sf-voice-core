// pure helpers for the timeline view. constants here so phase F can
// extract to a constants module on second use (CLAUDE.md rule 21).

import type { Transcript } from "./api";

// v1 defaults. per-org configurable thresholds are in core/TODO.md.
export const INTERRUPT_OVERLAP_MS = 200;
export const SLOW_TURN_MS = 1500;
export const DEAD_AIR_MS = 3000;

// zoom is expressed as pixels-per-millisecond. range covers ~30s on a
// 1440-wide laptop screen (zoom 0.05) down to ~1.5s per screen (zoom 1).
export const MIN_ZOOM = 0.02;
export const MAX_ZOOM = 1;
export const DEFAULT_ZOOM = 0.08;

export function msToPx(ms: number, pxPerMs: number): number {
  return ms * pxPerMs;
}

export function pxToMs(px: number, pxPerMs: number): number {
  return px / pxPerMs;
}

export function fmtMs(ms: number): string {
  if (ms < 0 || !Number.isFinite(ms)) return "0:00.0";
  const total = Math.max(0, ms);
  const m = Math.floor(total / 60_000);
  const s = (total % 60_000) / 1000;
  return `${m}:${s.toFixed(1).padStart(4, "0")}`;
}

export type Interrupt = {
  ai_id: number;
  caller_id: number;
  start_ms: number;
  end_ms: number;
  overlap_ms: number;
};

// any AI utterance that begins while a caller utterance is still active
// and overlaps by more than the threshold. one row per interrupt, ai
// utterance perspective.
export function findInterrupts(
  transcripts: Transcript[],
  thresholdMs = INTERRUPT_OVERLAP_MS,
): Interrupt[] {
  const ai = transcripts.filter((t) => t.speaker_label === "ai");
  const caller = transcripts.filter((t) => t.speaker_label === "caller");
  const out: Interrupt[] = [];
  for (const a of ai) {
    for (const c of caller) {
      const overlap = Math.min(a.end_ms, c.end_ms) - Math.max(a.start_ms, c.start_ms);
      if (overlap > thresholdMs) {
        // only count if ai *started* during caller (real interrupt).
        if (a.start_ms >= c.start_ms && a.start_ms <= c.end_ms) {
          out.push({
            ai_id: a.id,
            caller_id: c.id,
            start_ms: a.start_ms,
            end_ms: Math.min(a.end_ms, c.end_ms),
            overlap_ms: overlap,
          });
        }
      }
    }
  }
  return out;
}

export type Turnaround = {
  from_id: number;
  to_id: number;
  from_speaker: Transcript["speaker_label"];
  to_speaker: Transcript["speaker_label"];
  gap_ms: number;
  start_ms: number;
  end_ms: number;
};

// adjacent speaker changes: caller ends → ai starts (or vice versa).
// gap can be negative (overlap = interrupt) or large (dead air).
export function findTurnarounds(transcripts: Transcript[]): Turnaround[] {
  const sorted = [...transcripts].sort((a, b) => a.start_ms - b.start_ms);
  const out: Turnaround[] = [];
  for (let i = 1; i < sorted.length; i++) {
    const prev = sorted[i - 1];
    const cur = sorted[i];
    if (prev.speaker_label !== cur.speaker_label) {
      out.push({
        from_id: prev.id,
        to_id: cur.id,
        from_speaker: prev.speaker_label,
        to_speaker: cur.speaker_label,
        gap_ms: cur.start_ms - prev.end_ms,
        start_ms: prev.end_ms,
        end_ms: cur.start_ms,
      });
    }
  }
  return out;
}

export function totalDurationMs(transcripts: Transcript[]): number {
  if (transcripts.length === 0) return 0;
  return Math.max(...transcripts.map((t) => t.end_ms));
}
