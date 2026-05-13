// /calls/$callId — the timeline view. phase F fills this in with
// multitrack audio + transcripts + events. phase E ships the shell.

import { Link, createRoute } from "@tanstack/react-router";
import { useCall, useTranscripts } from "@/lib/queries";
import { rootRoute } from "./root";

function CallDetailPage() {
  const { callId } = callDetailRoute.useParams();
  const { data: call, isLoading, error } = useCall(callId);
  const { data: transcripts } = useTranscripts(callId);

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
    <div className="px-8 py-6">
      <Link to="/" className="text-sm text-neutral-400 hover:text-neutral-100">
        ← back to calls
      </Link>
      <header className="mt-4 flex items-baseline justify-between">
        <div>
          <h1 className="text-lg font-semibold tracking-tight">
            call <span className="font-mono">{call.id}</span>
          </h1>
          <p className="mt-1 text-xs text-neutral-500">
            from {call.caller_number ?? "unknown"} ·{" "}
            {new Date(call.started_at).toLocaleString()}
          </p>
        </div>
      </header>

      <section className="mt-8 rounded-lg border border-dashed border-neutral-800 px-6 py-12 text-center">
        <h3 className="text-sm font-medium text-neutral-200">
          timeline coming in phase F
        </h3>
        <p className="mt-1 text-sm text-neutral-500">
          {transcripts && transcripts.length > 0
            ? `${transcripts.length} utterances loaded — multitrack render is next.`
            : "no transcripts yet for this call."}
        </p>
      </section>
    </div>
  );
}

export const callDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/calls/$callId",
  component: CallDetailPage,
});
