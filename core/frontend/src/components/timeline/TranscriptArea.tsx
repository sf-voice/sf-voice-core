// two-row transcript display: caller above, AI below. interrupts render
// as red bands spanning both rows; turnaround latencies render as
// labeled brackets between adjacent utterances.

import type { Transcript } from "@/lib/api";
import {
  SLOW_TURN_MS,
  findInterrupts,
  findTurnarounds,
  msToPx,
  fmtMs,
} from "@/lib/timeline";
import { cn } from "@/lib/utils";

type Props = {
  transcripts: Transcript[];
  pxPerMs: number;
  rowHeight?: number;
  onSelectUtterance?: (t: Transcript) => void;
  selectedId?: number | null;
};

export function TranscriptArea({
  transcripts,
  pxPerMs,
  rowHeight = 36,
  onSelectUtterance,
  selectedId = null,
}: Props) {
  const caller = transcripts.filter((t) => t.speaker_label === "caller");
  const ai = transcripts.filter((t) => t.speaker_label === "ai");
  const interrupts = findInterrupts(transcripts);
  const turns = findTurnarounds(transcripts);

  const totalHeight = rowHeight * 2 + 28; // 28 for the latency strip at the bottom

  return (
    <div className="relative" style={{ height: totalHeight }}>
      {/* row labels gutter */}
      <RowLabel y={0} label="caller" />
      <RowLabel y={rowHeight} label="ai" />

      {/* utterance pills */}
      <div className="absolute inset-0">
        {caller.map((t) => (
          <UtterancePill
            key={t.id}
            t={t}
            y={0}
            pxPerMs={pxPerMs}
            height={rowHeight - 4}
            tone="caller"
            selected={selectedId === t.id}
            onClick={() => onSelectUtterance?.(t)}
          />
        ))}
        {ai.map((t) => (
          <UtterancePill
            key={t.id}
            t={t}
            y={rowHeight}
            pxPerMs={pxPerMs}
            height={rowHeight - 4}
            tone="ai"
            selected={selectedId === t.id}
            onClick={() => onSelectUtterance?.(t)}
          />
        ))}
      </div>

      {/* interrupt highlights span both rows */}
      <div className="absolute inset-x-0 pointer-events-none" style={{ top: 0, height: rowHeight * 2 }}>
        {interrupts.map((i, idx) => (
          <div
            key={`int-${idx}`}
            className="absolute bg-red-500/15 border-x border-red-500/60"
            style={{
              left: msToPx(i.start_ms, pxPerMs),
              width: msToPx(i.end_ms - i.start_ms, pxPerMs),
              top: 0,
              height: rowHeight * 2,
            }}
            title={`interrupt: ${i.overlap_ms}ms overlap`}
          />
        ))}
      </div>

      {/* turnaround latency strip below ai row */}
      <div
        className="absolute inset-x-0 pointer-events-none"
        style={{ top: rowHeight * 2, height: 28 }}
      >
        {turns
          .filter((t) => t.gap_ms > 0) // overlaps already shown as interrupts above
          .map((t, idx) => (
            <div
              key={`turn-${idx}`}
              className={cn(
                "absolute flex items-center justify-center text-[10px] font-mono px-1 rounded-sm border",
                t.gap_ms > SLOW_TURN_MS
                  ? "border-amber-500/70 text-amber-300 bg-amber-500/10"
                  : "border-neutral-800 text-neutral-200 bg-neutral-900/40",
              )}
              style={{
                left: msToPx(t.start_ms, pxPerMs),
                width: Math.max(20, msToPx(t.gap_ms, pxPerMs)),
                top: 6,
                height: 16,
              }}
              title={`${t.from_speaker} → ${t.to_speaker}: ${t.gap_ms}ms gap (${fmtMs(t.start_ms)})`}
            >
              {t.gap_ms}ms
            </div>
          ))}
      </div>
    </div>
  );
}

function RowLabel({ y, label }: { y: number; label: string }) {
  return (
    <div
      className="absolute left-0 text-[10px] uppercase tracking-wider text-neutral-300 font-mono"
      style={{ top: y + 2 }}
    >
      {label}
    </div>
  );
}

function UtterancePill({
  t,
  y,
  pxPerMs,
  height,
  tone,
  selected,
  onClick,
}: {
  t: Transcript;
  y: number;
  pxPerMs: number;
  height: number;
  tone: "ai" | "caller";
  selected: boolean;
  onClick: () => void;
}) {
  const left = msToPx(t.start_ms, pxPerMs);
  const width = Math.max(8, msToPx(t.end_ms - t.start_ms, pxPerMs));

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "absolute rounded px-1.5 text-[11px] overflow-hidden whitespace-nowrap text-ellipsis text-left border transition-colors",
        tone === "caller"
          ? "bg-sky-500/10 border-sky-500/40 text-sky-200 hover:bg-sky-500/20"
          : "bg-emerald-500/10 border-emerald-500/40 text-emerald-200 hover:bg-emerald-500/20",
        selected && "ring-1 ring-neutral-100 ring-offset-1 ring-offset-neutral-950",
      )}
      style={{ left, width, top: y + 2, height }}
      title={`${tone} · ${fmtMs(t.start_ms)} – ${fmtMs(t.end_ms)} · ${t.text}`}
    >
      {t.text}
    </button>
  );
}
