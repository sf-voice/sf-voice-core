// procedurally-generated waveform / event track for the empty dashboard.
// no audio engine — pure SVG with deterministic seeded noise so each
// track looks the same on every render, no jank, no react re-paints.

import { useMemo } from "react";

export type TrackKind = "wave" | "vad" | "dots" | "bars";

type Props = {
  label: string;
  kind: TrackKind;
  /// watercolor hue hex from BRAND.md.
  color: string;
  /// 0..1, controls overall amplitude.
  intensity?: number;
  /// distinct seed per track so they don't all look identical.
  seed: number;
  /// number of horizontal samples / events to render.
  samples?: number;
};

// Mulberry32 — small, deterministic, plenty random for visuals.
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generatePeaks(seed: number, count: number, intensity: number): number[] {
  const r = rng(seed);
  const peaks: number[] = [];
  let drift = 0;
  for (let i = 0; i < count; i++) {
    drift += (r() - 0.5) * 0.3;
    drift = Math.max(-0.9, Math.min(0.9, drift));
    const burst = r() > 0.85 ? r() * 0.6 : 0;
    const v = Math.abs(drift) * 0.6 + burst + r() * 0.2;
    peaks.push(Math.min(1, v) * intensity);
  }
  return peaks;
}

export function MockTrack({
  label,
  kind,
  color,
  intensity = 0.85,
  seed,
  samples = 140,
}: Props) {
  const peaks = useMemo(
    () => generatePeaks(seed, samples, intensity),
    [seed, samples, intensity],
  );

  // svg coords are 0..1000 horizontally, normalised by viewBox; rspack
  // will scale to whatever width the parent gives.
  const W = 1000;
  const H = 100;

  return (
    <div className="flex items-center gap-3 select-none">
      <div
        className="w-20 shrink-0 text-[10px] font-mono uppercase tracking-wider opacity-50"
        style={{ color }}
      >
        {label}
      </div>
      <div className="flex-1 min-w-0 relative">
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          className="w-full h-full"
        >
          {kind === "wave" && renderWave(peaks, W, H, color)}
          {kind === "vad" && renderVad(peaks, W, H, color)}
          {kind === "dots" && renderDots(peaks, W, H, color, seed)}
          {kind === "bars" && renderBars(peaks, W, H, color, seed)}
        </svg>
      </div>
    </div>
  );
}

function renderWave(peaks: number[], W: number, H: number, color: string) {
  const barW = W / peaks.length;
  const cx = H / 2;
  return (
    <g fill={color} opacity={0.8}>
      {peaks.map((p, i) => {
        const h = Math.max(1.5, p * H * 0.9);
        return (
          <rect
            key={i}
            x={i * barW}
            y={cx - h / 2}
            width={Math.max(1, barW - 0.6)}
            height={h}
            rx={0.6}
          />
        );
      })}
    </g>
  );
}

function renderVad(peaks: number[], W: number, H: number, color: string) {
  // step-fill: threshold the peaks to a binary band.
  let d = `M 0 ${H} `;
  peaks.forEach((p, i) => {
    const x = (i / peaks.length) * W;
    const active = p > 0.35;
    const y = active ? H * 0.2 : H * 0.85;
    d += `L ${x} ${y} `;
  });
  d += `L ${W} ${H} Z`;
  return <path d={d} fill={color} opacity={0.55} />;
}

function renderDots(peaks: number[], W: number, H: number, color: string, seed: number) {
  // sparse markers — pick ~8% of samples as "events".
  const r = rng(seed * 31 + 7);
  const dots: { x: number; y: number; size: number }[] = [];
  peaks.forEach((p, i) => {
    if (r() < 0.08 + p * 0.05) {
      dots.push({
        x: (i / peaks.length) * W,
        y: H / 2 + (r() - 0.5) * H * 0.5,
        size: 3 + r() * 4,
      });
    }
  });
  return (
    <g fill={color}>
      {dots.map((d, i) => (
        <circle key={i} cx={d.x} cy={d.y} r={d.size} opacity={0.85} />
      ))}
    </g>
  );
}

function renderBars(peaks: number[], W: number, H: number, color: string, seed: number) {
  // 3-6 horizontal bars representing tool-call durations.
  const r = rng(seed * 13 + 3);
  const bars: { x: number; w: number }[] = [];
  let cursor = 0.05;
  while (cursor < 0.92 && bars.length < 6) {
    const w = 0.05 + r() * 0.18;
    bars.push({ x: cursor, w });
    cursor += w + 0.03 + r() * 0.25;
  }
  void peaks; // peaks ignored — bars use their own random layout
  return (
    <g fill={color} opacity={0.7}>
      {bars.map((b, i) => (
        <rect
          key={i}
          x={b.x * W}
          y={H * 0.35}
          width={b.w * W}
          height={H * 0.3}
          rx={4}
        />
      ))}
    </g>
  );
}
