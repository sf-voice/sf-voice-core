// timeline orchestrator. owns zoom, playhead, selection. composes the
// audio + transcript area + playhead + drag-select overlay. wires
// keyboard: space play/pause, J/L scrub, I/O in/out markers.

import { useCallback, useEffect, useRef, useState } from "react";
import type { Call, Transcript } from "@/lib/api";
import {
  DEFAULT_ZOOM,
  MAX_ZOOM,
  MIN_ZOOM,
  fmtMs,
  msToPx,
  totalDurationMs,
} from "@/lib/timeline";
import { WaveformTrack } from "./WaveformTrack";
import { TranscriptArea } from "./TranscriptArea";
import { Playhead } from "./Playhead";
import { Selection, type Range } from "./Selection";
import { SidePanel } from "./SidePanel";

type Props = {
  call: Call;
  transcripts: Transcript[];
  onInsertPrompt: (range: Range) => void;
};

const TRACK_LEFT_PAD = 56; // gutter for row labels
const RULER_HEIGHT = 22;
const WAVEFORM_HEIGHT = 56;
const TRANSCRIPT_AREA_HEIGHT = 36 * 2 + 28; // matches TranscriptArea default

export function Timeline({ call, transcripts, onInsertPrompt }: Props) {
  const [zoom, setZoom] = useState(DEFAULT_ZOOM);
  const [playheadMs, setPlayheadMs] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [audioDurationMs, setAudioDurationMs] = useState(0);
  const [range, setRange] = useState<Range | null>(null);
  const [selectedUtterance, setSelectedUtterance] = useState<Transcript | null>(
    null,
  );

  const transcriptDur = totalDurationMs(transcripts);
  const totalMs = Math.max(transcriptDur, audioDurationMs, 1000);
  const widthPx = Math.max(800, msToPx(totalMs, zoom));

  const scrollerRef = useRef<HTMLDivElement | null>(null);

  // keep playhead in view when playing.
  useEffect(() => {
    const el = scrollerRef.current;
    if (!el || !playing) return;
    const xPx = msToPx(playheadMs, zoom);
    const viewLeft = el.scrollLeft;
    const viewRight = viewLeft + el.clientWidth;
    if (xPx < viewLeft + 80 || xPx > viewRight - 80) {
      el.scrollTo({ left: xPx - el.clientWidth / 2, behavior: "smooth" });
    }
  }, [playheadMs, playing, zoom]);

  const handleTimeUpdate = useCallback((ms: number) => {
    setPlayheadMs(ms);
  }, []);

  const handleDuration = useCallback((ms: number) => {
    setAudioDurationMs(ms);
  }, []);

  // keyboard shortcuts. scoped to window — debugger needs them anywhere
  // on the page. ignore if typing in an input.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const tag = (e.target as HTMLElement | null)?.tagName?.toLowerCase();
      if (tag === "input" || tag === "textarea") return;

      if (e.code === "Space") {
        e.preventDefault();
        setPlaying((p) => !p);
      } else if (e.key === "j") {
        e.preventDefault();
        setPlayheadMs((m) => Math.max(0, m - 2000));
      } else if (e.key === "k") {
        e.preventDefault();
        setPlaying(false);
      } else if (e.key === "l") {
        e.preventDefault();
        setPlayheadMs((m) => Math.min(totalMs, m + 2000));
      } else if (e.key === "i") {
        e.preventDefault();
        setRange((r) =>
          r
            ? { startMs: playheadMs, endMs: Math.max(playheadMs, r.endMs) }
            : { startMs: playheadMs, endMs: playheadMs + 1000 },
        );
      } else if (e.key === "o") {
        e.preventDefault();
        setRange((r) =>
          r
            ? { startMs: Math.min(playheadMs, r.startMs), endMs: playheadMs }
            : { startMs: Math.max(0, playheadMs - 1000), endMs: playheadMs },
        );
      } else if (e.key === "+" || e.key === "=") {
        e.preventDefault();
        setZoom((z) => Math.min(MAX_ZOOM, z * 1.25));
      } else if (e.key === "-") {
        e.preventDefault();
        setZoom((z) => Math.max(MIN_ZOOM, z / 1.25));
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [playheadMs, totalMs]);

  return (
    <div className="flex border-t border-neutral-900">
      <div className="flex-1 min-w-0 flex flex-col">
        <Toolbar
          playing={playing}
          onTogglePlay={() => setPlaying((p) => !p)}
          zoom={zoom}
          onZoom={(z) => setZoom(Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, z)))}
          playheadMs={playheadMs}
          totalMs={totalMs}
        />

        <div
          ref={scrollerRef}
          className="overflow-x-auto"
          style={{ maxHeight: "70vh" }}
        >
          <div
            className="relative"
            style={{ width: widthPx + TRACK_LEFT_PAD, paddingLeft: TRACK_LEFT_PAD }}
          >
            {/* ruler */}
            <Ruler totalMs={totalMs} pxPerMs={zoom} height={RULER_HEIGHT} />

            {/* waveform */}
            <div className="mt-2">
              <WaveformTrack
                audioUrl={call.audio_uri}
                widthPx={widthPx}
                heightPx={WAVEFORM_HEIGHT}
                color="#525252"
                onTimeUpdate={handleTimeUpdate}
                onDuration={handleDuration}
                playheadMs={playheadMs}
                playing={playing}
              />
            </div>

            {/* transcript pills + interrupts + latencies */}
            <div className="mt-2 relative">
              <TranscriptArea
                transcripts={transcripts}
                pxPerMs={zoom}
                selectedId={selectedUtterance?.id ?? null}
                onSelectUtterance={(t) => {
                  setSelectedUtterance(t);
                  setRange(null);
                  setPlayheadMs(t.start_ms);
                }}
              />
            </div>

            {/* drag-select overlay covers ruler + waveform + transcripts.
               sized to the full timeline body height. */}
            <Selection
              pxPerMs={zoom}
              height={
                RULER_HEIGHT + 8 + WAVEFORM_HEIGHT + 8 + TRANSCRIPT_AREA_HEIGHT
              }
              selection={range}
              onChange={(r) => {
                setRange(r);
                if (r) setSelectedUtterance(null);
              }}
            />

            {/* playhead */}
            <Playhead
              ms={playheadMs}
              pxPerMs={zoom}
              height={
                RULER_HEIGHT + 8 + WAVEFORM_HEIGHT + 8 + TRANSCRIPT_AREA_HEIGHT
              }
            />
          </div>
        </div>

        <KeyboardHints />
      </div>

      <SidePanel
        callId={call.id}
        range={range}
        utterance={selectedUtterance}
        transcripts={transcripts}
        onClear={() => {
          setRange(null);
          setSelectedUtterance(null);
        }}
        onInsertPrompt={(r) => onInsertPrompt(r)}
      />
    </div>
  );
}

function Toolbar({
  playing,
  onTogglePlay,
  zoom,
  onZoom,
  playheadMs,
  totalMs,
}: {
  playing: boolean;
  onTogglePlay: () => void;
  zoom: number;
  onZoom: (z: number) => void;
  playheadMs: number;
  totalMs: number;
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-2 border-b border-neutral-900 text-sm">
      <button
        type="button"
        onClick={onTogglePlay}
        className="rounded-md bg-neutral-100 text-neutral-900 px-2.5 py-1 text-xs font-medium hover:bg-white"
        title="space"
      >
        {playing ? "pause" : "play"}
      </button>
      <span className="font-mono text-xs text-neutral-400">
        {fmtMs(playheadMs)} / {fmtMs(totalMs)}
      </span>
      <div className="flex-1" />
      <div className="flex items-center gap-1 text-xs">
        <button
          type="button"
          onClick={() => onZoom(zoom / 1.25)}
          className="px-2 py-0.5 rounded border border-neutral-800 text-neutral-400 hover:text-neutral-100"
        >
          −
        </button>
        <span className="font-mono text-neutral-500 w-20 text-center">
          {(zoom * 1000).toFixed(0)} px/s
        </span>
        <button
          type="button"
          onClick={() => onZoom(zoom * 1.25)}
          className="px-2 py-0.5 rounded border border-neutral-800 text-neutral-400 hover:text-neutral-100"
        >
          +
        </button>
      </div>
    </div>
  );
}

function Ruler({
  totalMs,
  pxPerMs,
  height,
}: {
  totalMs: number;
  pxPerMs: number;
  height: number;
}) {
  // tick every second by default, every 5s when zoomed out.
  const tickEveryMs = pxPerMs < 0.05 ? 5000 : 1000;
  const ticks: number[] = [];
  for (let ms = 0; ms <= totalMs; ms += tickEveryMs) ticks.push(ms);
  return (
    <div
      className="relative border-b border-neutral-900"
      style={{ height, width: msToPx(totalMs, pxPerMs) }}
    >
      {ticks.map((ms) => (
        <div
          key={ms}
          className="absolute top-0 text-[10px] font-mono text-neutral-600"
          style={{ left: msToPx(ms, pxPerMs) }}
        >
          <div className="border-l border-neutral-800 h-2 w-px" />
          <div className="pl-1 pt-0.5">{fmtMs(ms)}</div>
        </div>
      ))}
    </div>
  );
}

function KeyboardHints() {
  return (
    <div className="px-4 py-2 border-t border-neutral-900 text-[11px] text-neutral-600 font-mono flex flex-wrap gap-x-4 gap-y-1">
      <Hint k="space" v="play / pause" />
      <Hint k="j / l" v="scrub ±2s" />
      <Hint k="k" v="pause" />
      <Hint k="i / o" v="in / out" />
      <Hint k="+ / −" v="zoom" />
    </div>
  );
}

function Hint({ k, v }: { k: string; v: string }) {
  return (
    <span>
      <span className="text-neutral-400">{k}</span>{" "}
      <span className="text-neutral-600">{v}</span>
    </span>
  );
}
