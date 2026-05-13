// vertical scrub line that floats above all tracks.

import { msToPx } from "@/lib/timeline";

export function Playhead({
  ms,
  pxPerMs,
  height,
}: {
  ms: number;
  pxPerMs: number;
  height: number;
}) {
  return (
    <div
      className="absolute top-0 pointer-events-none w-px bg-amber-400/80"
      style={{ left: msToPx(ms, pxPerMs), height }}
    >
      <div className="absolute -top-1.5 -translate-x-1/2 w-3 h-3 rotate-45 bg-amber-400/90 rounded-sm" />
    </div>
  );
}
