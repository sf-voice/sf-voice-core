// wavesurfer wrapper for one audio track. wraps v7's instance lifecycle
// and forwards play/seek up to Timeline via callbacks.

import { useEffect, useRef } from "react";
import WaveSurfer from "wavesurfer.js";

type Props = {
  audioUrl: string | null;
  // total timeline width in pixels — wavesurfer fits its waveform to its
  // container, so the parent sets width via pxPerMs * durationMs.
  widthPx: number;
  heightPx?: number;
  color: string;
  cursorColor?: string;
  // notifies the timeline when the user clicks to seek on this waveform
  // (or wavesurfer fires timeupdate from playback).
  onTimeUpdate?: (ms: number) => void;
  onDuration?: (ms: number) => void;
  // playhead seconds, drives wavesurfer.seekTo when changed externally.
  playheadMs: number;
  // playing state — drives wavesurfer.play()/pause().
  playing: boolean;
};

export function WaveformTrack({
  audioUrl,
  widthPx,
  heightPx = 56,
  color,
  cursorColor = "#fbbf24",
  onTimeUpdate,
  onDuration,
  playheadMs,
  playing,
}: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const wsRef = useRef<WaveSurfer | null>(null);
  const durationMsRef = useRef<number>(0);

  // create instance once per audioUrl. unmount cleans up.
  useEffect(() => {
    const el = containerRef.current;
    if (!el || !audioUrl) return;

    const ws = WaveSurfer.create({
      container: el,
      height: heightPx,
      waveColor: color,
      progressColor: color,
      cursorColor,
      cursorWidth: 1,
      barWidth: 2,
      barGap: 1,
      barRadius: 1,
      normalize: true,
      interact: true,
      url: audioUrl,
    });
    wsRef.current = ws;

    const onReady = () => {
      const sec = ws.getDuration();
      durationMsRef.current = sec * 1000;
      onDuration?.(durationMsRef.current);
    };
    const onTime = (sec: number) => onTimeUpdate?.(sec * 1000);
    const onSeeking = (sec: number) => onTimeUpdate?.(sec * 1000);

    ws.on("ready", onReady);
    ws.on("timeupdate", onTime);
    ws.on("seeking", onSeeking);

    return () => {
      ws.destroy();
      wsRef.current = null;
    };
    // intentionally only re-init when audioUrl changes; the rest are
    // driven by the effects below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audioUrl]);

  // sync playhead externally → wavesurfer.
  useEffect(() => {
    const ws = wsRef.current;
    if (!ws) return;
    const dur = durationMsRef.current;
    if (dur <= 0) return;
    const targetRatio = Math.min(1, Math.max(0, playheadMs / dur));
    const wsRatio = ws.getCurrentTime() / Math.max(0.001, ws.getDuration());
    // only call seekTo when meaningfully different — avoids feedback
    // loops with wavesurfer's own timeupdate events.
    if (Math.abs(targetRatio - wsRatio) > 0.005) {
      ws.seekTo(targetRatio);
    }
  }, [playheadMs]);

  // sync playing state.
  useEffect(() => {
    const ws = wsRef.current;
    if (!ws) return;
    if (playing && !ws.isPlaying()) {
      // play returns a promise; ignore rejection (autoplay gate).
      ws.play().catch(() => {});
    } else if (!playing && ws.isPlaying()) {
      ws.pause();
    }
  }, [playing]);

  if (!audioUrl) {
    return (
      <div
        style={{ width: widthPx, height: heightPx }}
        className="rounded bg-neutral-900/60 border border-dashed border-neutral-800 flex items-center justify-center text-xs text-neutral-300"
      >
        no audio
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      style={{ width: widthPx, height: heightPx }}
      className="rounded bg-neutral-900/40"
    />
  );
}
