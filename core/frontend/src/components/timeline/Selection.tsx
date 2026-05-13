// drag-select overlay. captures mouse down/move/up on the timeline lane
// and reports {startMs, endMs}. also renders the selection rect.

import { useEffect, useRef, useState } from "react";
import { msToPx, pxToMs } from "@/lib/timeline";

export type Range = { startMs: number; endMs: number };

type Props = {
  pxPerMs: number;
  height: number;
  selection: Range | null;
  onChange: (r: Range | null) => void;
};

export function Selection({ pxPerMs, height, selection, onChange }: Props) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const [drag, setDrag] = useState<{ start: number; end: number } | null>(null);

  // listen at the root element instead of window — keeps drag within the
  // timeline column even when the user slips upward.
  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;

    function onDown(e: MouseEvent) {
      if (!el) return;
      // shift-click on an existing pill is for utterance-select; only
      // start a range drag when the click target is the lane itself.
      if (e.target !== el) return;
      const rect = el.getBoundingClientRect();
      const x = e.clientX - rect.left + el.scrollLeft;
      setDrag({ start: x, end: x });
      onChange(null);
    }
    function onMove(e: MouseEvent) {
      if (!drag || !el) return;
      const rect = el.getBoundingClientRect();
      const x = e.clientX - rect.left + el.scrollLeft;
      setDrag({ start: drag.start, end: x });
    }
    function onUp() {
      if (!drag) return;
      const a = Math.min(drag.start, drag.end);
      const b = Math.max(drag.start, drag.end);
      if (b - a > 4) {
        onChange({
          startMs: Math.max(0, pxToMs(a, pxPerMs)),
          endMs: pxToMs(b, pxPerMs),
        });
      }
      setDrag(null);
    }

    el.addEventListener("mousedown", onDown);
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    return () => {
      el.removeEventListener("mousedown", onDown);
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    };
  }, [drag, pxPerMs, onChange]);

  const active = drag
    ? {
        left: Math.min(drag.start, drag.end),
        width: Math.abs(drag.end - drag.start),
      }
    : selection
      ? {
          left: msToPx(selection.startMs, pxPerMs),
          width: msToPx(selection.endMs - selection.startMs, pxPerMs),
        }
      : null;

  return (
    <div
      ref={rootRef}
      className="absolute inset-0 cursor-text"
      style={{ height }}
    >
      {active && (
        <div
          className="absolute top-0 bg-neutral-100/10 border-l border-r border-neutral-100/40 pointer-events-none"
          style={{ left: active.left, width: active.width, height }}
        />
      )}
    </div>
  );
}
