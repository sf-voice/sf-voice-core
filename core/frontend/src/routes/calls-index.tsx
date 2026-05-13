// GET / — the call list. primary landing screen.

import { createRoute } from "@tanstack/react-router";
import { CallList } from "@/components/CallList";
import { useCalls } from "@/lib/queries";
import { authedLayoutRoute } from "./_authed";

function CallsIndexPage() {
  const { data, isLoading, error } = useCalls();

  return (
    <div className="px-8 py-6">
      <header className="flex items-baseline justify-between mb-6">
        <h1 className="text-lg font-semibold tracking-tight">calls</h1>
        <div className="text-xs text-neutral-500">
          {data ? `${data.length} call${data.length === 1 ? "" : "s"}` : null}
        </div>
      </header>
      {isLoading ? (
        <div className="text-sm text-neutral-500">loading…</div>
      ) : error ? (
        <ErrorState message={(error as Error).message} />
      ) : (
        <CallList calls={data ?? []} />
      )}
    </div>
  );
}

function ErrorState({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-red-900/60 bg-red-950/30 px-4 py-3 text-sm text-red-200">
      <div className="font-medium">api error</div>
      <div className="mt-1 font-mono text-xs text-red-300/80">{message}</div>
      <div className="mt-2 text-xs text-red-300/60">
        is sf-voice-api running on :8080? try{" "}
        <code className="font-mono">cargo run -p sf-voice-api</code>.
      </div>
    </div>
  );
}

export const callsIndexRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/",
  component: CallsIndexPage,
});
