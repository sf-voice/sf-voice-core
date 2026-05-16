// /calls/$callId/slices/$sliceId — direct deep-link to a slice. shows
// the prompt + reasoning path + A/B audio + PR url. the in-call
// drawer flow is the primary path; this page exists so slack messages
// and shared urls can land on a specific slice.

import { Link, createRoute } from "@tanstack/react-router";
import { useCall, useSlice } from "@/lib/queries";
import { ReasoningPath } from "@/components/prompt/ReasoningPath";
import { ABPlayer } from "@/components/call/ABPlayer";
import { fmtMs } from "@/lib/timeline";
import { authedLayoutRoute } from "../_authed";

const SANDBOX_STEPS = [
  "slice captured",
  "context assembled",
  "sandbox provisioned",
  "regenerating AI response",
  "rendering TTS audio",
  "opening PR",
  "awaiting review",
];

function SliceDetailPage() {
  const { callId, sliceId } = sliceDetailRoute.useParams();
  const { data: slice, isLoading } = useSlice(sliceId);
  const { data: call } = useCall(callId);

  if (isLoading) {
    return (
      <div className="px-8 py-6 text-sm text-neutral-500">loading slice…</div>
    );
  }

  if (!slice) {
    return (
      <div className="px-8 py-6">
        <Link
          to="/calls/$callId"
          params={{ callId }}
          className="text-sm text-neutral-400 hover:text-neutral-100"
        >
          ← back to call
        </Link>
        <p className="mt-6 text-sm text-neutral-400">
          slice <span className="font-mono">{sliceId}</span> not found.
        </p>
      </div>
    );
  }

  return (
    <div className="px-8 py-6 max-w-3xl">
      <Link
        to="/calls/$callId"
        params={{ callId }}
        className="text-xs text-neutral-500 hover:text-neutral-100"
      >
        ← back to call
      </Link>

      <header className="mt-4">
        <h1 className="text-base font-semibold tracking-tight">
          slice <span className="font-mono text-neutral-400">{slice.id}</span>
        </h1>
        <p className="mt-1 text-xs text-neutral-500">
          {fmtMs(slice.start_ms)} – {fmtMs(slice.end_ms)} · status:{" "}
          {slice.status}
        </p>
      </header>

      <section className="mt-6">
        <div className="text-xs uppercase tracking-wider text-neutral-500 mb-1">
          prompt
        </div>
        <p className="text-sm text-neutral-100 whitespace-pre-wrap">
          {slice.prompt_text}
        </p>
      </section>

      {slice.job_id && (
        <section className="mt-6">
          <div className="text-xs uppercase tracking-wider text-neutral-500 mb-2">
            reasoning path
          </div>
          <ReasoningPath
            jobId={slice.job_id}
            expectedSteps={SANDBOX_STEPS}
          />
        </section>
      )}

      {slice.status === "pr_open" && (
        <section className="mt-6">
          <ABPlayer
            originalUrl={call?.audio_uri ?? null}
            regeneratedUrl={null}
            prUrl={slice.pr_url}
          />
        </section>
      )}
    </div>
  );
}

export const sliceDetailRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/calls/$callId/slices/$sliceId",
  component: SliceDetailPage,
});
