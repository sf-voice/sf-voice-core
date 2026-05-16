// prompt input for a selected slice. shows the range, the utterances
// in range as context, a textarea, submit + cancel.

import { useState } from "react";
import type { Transcript } from "@/lib/api";
import { useCreateSlice } from "@/lib/queries";
import { fmtMs } from "@/lib/timeline";

type Props = {
  callId: string;
  range: { startMs: number; endMs: number };
  transcripts: Transcript[];
  onSubmitted: (ids: { sliceId: string; jobId: string }) => void;
  onCancel: () => void;
};

export function PromptInput({
  callId,
  range,
  transcripts,
  onSubmitted,
  onCancel,
}: Props) {
  const [text, setText] = useState("");
  const create = useCreateSlice(callId);

  const inRange = transcripts.filter(
    (t) => t.end_ms > range.startMs && t.start_ms < range.endMs,
  );

  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        if (!text.trim()) return;
        create.mutate(
          {
            start_ms: Math.round(range.startMs),
            end_ms: Math.round(range.endMs),
            prompt_text: text.trim(),
          },
          {
            onSuccess: (data) => {
              onSubmitted({ sliceId: data.slice_id, jobId: data.job_id });
            },
          },
        );
      }}
    >
      <div>
        <div className="text-xs uppercase tracking-wider text-neutral-500">
          slice
        </div>
        <div className="mt-1 font-mono text-sm text-neutral-100">
          {fmtMs(range.startMs)} – {fmtMs(range.endMs)}{" "}
          <span className="text-neutral-500">
            ({Math.round(range.endMs - range.startMs)} ms ·{" "}
            {inRange.length} utterance{inRange.length === 1 ? "" : "s"})
          </span>
        </div>
      </div>

      <div className="max-h-32 overflow-auto rounded-md border border-neutral-900 bg-neutral-950 px-3 py-2 text-xs space-y-1">
        {inRange.length === 0 ? (
          <div className="text-neutral-600">no utterances in this range.</div>
        ) : (
          inRange.map((t) => (
            <div key={t.id}>
              <span className="font-mono text-neutral-500">
                {t.speaker_label} · {fmtMs(t.start_ms)}
              </span>{" "}
              <span className="text-neutral-300">{t.text}</span>
            </div>
          ))
        )}
      </div>

      <label className="block">
        <div className="text-xs uppercase tracking-wider text-neutral-500">
          your prompt
        </div>
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          rows={4}
          placeholder="e.g. the AI interrupted the caller here — try a slower turn-taking style and re-acknowledge the previous statement before moving on"
          className="mt-1 w-full rounded-md border border-neutral-800 bg-neutral-950 px-3 py-2 text-sm text-neutral-100 placeholder:text-neutral-700 focus:outline-none focus:ring-1 focus:ring-neutral-500"
          autoFocus
        />
      </label>

      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={create.isPending || !text.trim()}
          className="rounded-md bg-neutral-100 text-neutral-900 px-3 py-1.5 text-sm font-medium hover:bg-white disabled:opacity-40"
        >
          {create.isPending ? "submitting…" : "run sandbox"}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-neutral-800 text-neutral-300 px-3 py-1.5 text-sm hover:text-neutral-100"
        >
          cancel
        </button>
        {create.isError && (
          <span className="text-xs text-red-300">
            {(create.error as Error).message}
          </span>
        )}
      </div>
    </form>
  );
}
