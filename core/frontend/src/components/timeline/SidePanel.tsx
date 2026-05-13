// right-rail panel. populated when the user selects a range or clicks
// an utterance. ships with utterance list + insert-prompt cta that
// opens the prompt flow drawer (handled by the parent route).

import type { Transcript } from "@/lib/api";
import { fmtMs } from "@/lib/timeline";
import type { Range } from "./Selection";

type Props = {
  callId: string;
  range: Range | null;
  utterance: Transcript | null;
  transcripts: Transcript[];
  onClear: () => void;
  onInsertPrompt: (range: Range) => void;
};

export function SidePanel({
  callId: _callId,
  range,
  utterance,
  transcripts,
  onClear,
  onInsertPrompt,
}: Props) {
  const visible = range || utterance;

  if (!visible) {
    return (
      <aside className="w-80 shrink-0 border-l border-neutral-900 p-4 text-xs text-neutral-600">
        drag on the timeline to select a range, or click an utterance.
      </aside>
    );
  }

  const startMs = range ? range.startMs : utterance!.start_ms;
  const endMs = range ? range.endMs : utterance!.end_ms;
  const durationMs = Math.max(0, endMs - startMs);

  const inRange = transcripts.filter(
    (t) => t.end_ms > startMs && t.start_ms < endMs,
  );

  return (
    <aside className="w-80 shrink-0 border-l border-neutral-900 p-4 flex flex-col gap-4">
      <header className="flex items-center justify-between">
        <div>
          <div className="text-xs uppercase tracking-wider text-neutral-500">
            selection
          </div>
          <div className="mt-1 font-mono text-sm text-neutral-100">
            {fmtMs(startMs)} – {fmtMs(endMs)}
          </div>
          <div className="text-xs text-neutral-500">{durationMs} ms</div>
        </div>
        <button
          type="button"
          onClick={onClear}
          className="text-xs text-neutral-500 hover:text-neutral-100"
        >
          clear
        </button>
      </header>

      <section>
        <div className="text-xs uppercase tracking-wider text-neutral-500 mb-2">
          utterances in range
        </div>
        <ul className="space-y-1.5 max-h-72 overflow-auto">
          {inRange.length === 0 ? (
            <li className="text-xs text-neutral-600">none</li>
          ) : (
            inRange.map((t) => (
              <li
                key={t.id}
                className="text-xs leading-snug border-l-2 pl-2 py-0.5"
                style={{
                  borderColor:
                    t.speaker_label === "ai" ? "#10b981" : "#0ea5e9",
                }}
              >
                <div className="font-mono text-[10px] text-neutral-500">
                  {t.speaker_label} · {fmtMs(t.start_ms)}
                </div>
                <div className="text-neutral-200">{t.text}</div>
              </li>
            ))
          )}
        </ul>
      </section>

      <section>
        <button
          type="button"
          onClick={() =>
            onInsertPrompt({ startMs, endMs })
          }
          className="block w-full rounded-md bg-neutral-100 text-neutral-900 text-sm font-medium text-center py-2 hover:bg-white"
        >
          insert prompt →
        </button>
        <p className="mt-2 text-xs text-neutral-600">
          opens the sandbox flow. each step posts to your org's slack
          webhook.
        </p>
      </section>
    </aside>
  );
}
