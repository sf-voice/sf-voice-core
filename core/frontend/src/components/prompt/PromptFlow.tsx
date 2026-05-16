// orchestrator for "insert prompt → sandbox runs → A/B + PR".
// two modes: input (textarea), then tracking (reasoning path + A/B).
// hosted by ProgressDrawer.

import { useState } from "react";
import type { Transcript } from "@/lib/api";
import { useJobEvents } from "@/lib/events";
import { PromptInput } from "./PromptInput";
import { ReasoningPath } from "./ReasoningPath";
import { ABPlayer } from "../call/ABPlayer";
import { useSlice } from "@/lib/queries";

// canonical step order mirrors backend src/jobs/sandbox_stub.rs STEPS.
// keeps rows visible as pending before the backend emits them.
const SANDBOX_STEPS = [
  "slice captured",
  "context assembled",
  "sandbox provisioned",
  "regenerating AI response",
  "rendering TTS audio",
  "opening PR",
  "awaiting review",
];

type Props = {
  callId: string;
  range: { startMs: number; endMs: number };
  transcripts: Transcript[];
  originalAudioUrl: string | null;
  onClose: () => void;
};

export function PromptFlow({
  callId,
  range,
  transcripts,
  originalAudioUrl,
  onClose,
}: Props) {
  const [submitted, setSubmitted] = useState<{
    sliceId: string;
    jobId: string;
  } | null>(null);

  if (!submitted) {
    return (
      <PromptInput
        callId={callId}
        range={range}
        transcripts={transcripts}
        onSubmitted={setSubmitted}
        onCancel={onClose}
      />
    );
  }

  return (
    <PromptTracking
      sliceId={submitted.sliceId}
      jobId={submitted.jobId}
      originalAudioUrl={originalAudioUrl}
      onClose={onClose}
    />
  );
}

function PromptTracking({
  sliceId,
  jobId,
  originalAudioUrl,
  onClose,
}: {
  sliceId: string;
  jobId: string;
  originalAudioUrl: string | null;
  onClose: () => void;
}) {
  const { events } = useJobEvents(jobId);
  const { data: slice } = useSlice(sliceId);

  const done = events.some(
    (e) => e.step === "awaiting review" && e.status === "done",
  );

  return (
    <div className="space-y-4">
      <div className="flex items-baseline justify-between">
        <div>
          <div className="text-xs uppercase tracking-wider text-neutral-500">
            sandbox job
          </div>
          <div className="font-mono text-xs text-neutral-400">{jobId}</div>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="text-xs text-neutral-500 hover:text-neutral-100"
        >
          close
        </button>
      </div>

      <ReasoningPath jobId={jobId} expectedSteps={SANDBOX_STEPS} />

      {done && (
        <ABPlayer
          originalUrl={originalAudioUrl}
          regeneratedUrl={null}
          prUrl={slice?.pr_url ?? null}
        />
      )}
    </div>
  );
}
