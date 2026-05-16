// /calls/$callId — the timeline view. multitrack waveform + transcript
// pills + interrupt highlights + latency overlays + drag-select +
// keyboard scrub. side panel populates on selection. clicking
// "insert prompt" opens the slide-up drawer that runs the sandbox flow.

import { useState } from "react";
import { Link, createRoute } from "@tanstack/react-router";
import { useCall, useCreateTranscribeRun, useTranscripts } from "@/lib/queries";
import { Timeline } from "@/components/timeline/Timeline";
import { ProgressDrawer } from "@/components/call/ProgressDrawer";
import { PromptFlow } from "@/components/prompt/PromptFlow";
import { ReasoningPath } from "@/components/prompt/ReasoningPath";
import { authedLayoutRoute } from "../_authed";

function CallDetailPage() {
  const { callId } = callDetailRoute.useParams();
  const { data: call, isLoading, error } = useCall(callId);
  const { data: transcripts } = useTranscripts(callId);
  const retranscribe = useCreateTranscribeRun(callId);

  const [promptRange, setPromptRange] = useState<
    { startMs: number; endMs: number } | null
  >(null);
  const [retranscribeJobId, setRetranscribeJobId] = useState<string | null>(
    null,
  );

  if (isLoading) {
    return <div className="px-8 py-6 text-sm text-neutral-500">loading…</div>;
  }

  if (error) {
    return (
      <div className="px-8 py-6 text-sm text-red-300">
        error: {(error as Error).message}
      </div>
    );
  }

  if (!call) {
    return (
      <div className="px-8 py-6">
        <Link
          to="/"
          className="text-sm text-neutral-400 hover:text-neutral-100"
        >
          ← back to calls
        </Link>
        <p className="mt-6 text-sm text-neutral-400">
          call <span className="font-mono">{callId}</span> not found.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-screen">
      <header className="px-8 py-4 border-b border-neutral-900 flex items-start justify-between gap-4">
        <div>
          <Link
            to="/"
            className="text-xs text-neutral-500 hover:text-neutral-100"
          >
            ← back to calls
          </Link>
          <div className="mt-2 flex items-baseline gap-4">
            <h1 className="text-base font-semibold tracking-tight">
              call <span className="font-mono text-neutral-400">{call.id}</span>
            </h1>
            <span className="text-xs text-neutral-500">
              from {call.caller_number ?? "unknown"} ·{" "}
              {new Date(call.started_at).toLocaleString()}
            </span>
          </div>
        </div>
        <button
          type="button"
          onClick={() => {
            retranscribe.mutate(undefined, {
              onSuccess: (data) => setRetranscribeJobId(data.job_id),
            });
          }}
          disabled={retranscribe.isPending}
          className="rounded-md border border-neutral-800 text-neutral-300 px-3 py-1.5 text-xs hover:text-neutral-100 disabled:opacity-50"
        >
          {retranscribe.isPending ? "queueing…" : "re-transcribe"}
        </button>
      </header>
      <div className="flex-1 min-h-0">
        <Timeline
          call={call}
          transcripts={transcripts ?? []}
          onInsertPrompt={setPromptRange}
        />
      </div>

      <ProgressDrawer
        open={Boolean(promptRange)}
        onClose={() => setPromptRange(null)}
        title="insert prompt"
      >
        {promptRange && (
          <PromptFlow
            callId={call.id}
            range={promptRange}
            transcripts={transcripts ?? []}
            originalAudioUrl={call.audio_uri}
            onClose={() => setPromptRange(null)}
          />
        )}
      </ProgressDrawer>

      <ProgressDrawer
        open={Boolean(retranscribeJobId)}
        onClose={() => setRetranscribeJobId(null)}
        title="re-transcribe"
      >
        {retranscribeJobId && <ReasoningPath jobId={retranscribeJobId} />}
      </ProgressDrawer>
    </div>
  );
}

export const callDetailRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/calls/$callId",
  component: CallDetailPage,
});
