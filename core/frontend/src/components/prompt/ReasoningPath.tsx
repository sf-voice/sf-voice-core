// renders the streaming reasoning path. consumes job sse events,
// collapses to latest-per-step, and shows one row per step with a
// status glyph.

import { useJobEvents, latestPerStep, type StepEvent } from "@/lib/events";
import { cn } from "@/lib/utils";

type Props = {
  jobId: string;
  /// optional canonical step list; rows render in this order. if a step
  /// hasn't fired yet it shows as `pending`. if omitted, only seen
  /// steps are shown in their first-appearance order.
  expectedSteps?: string[];
};

export function ReasoningPath({ jobId, expectedSteps }: Props) {
  const { events, error } = useJobEvents(jobId);
  const latest = latestPerStep(events);

  const rows = expectedSteps
    ? expectedSteps.map((s) => latest.find((e) => e.step === s) ?? placeholder(s))
    : latest;

  return (
    <div className="rounded-lg border border-neutral-900 bg-neutral-950">
      <ul className="divide-y divide-neutral-900">
        {rows.map((ev) => (
          <li key={ev.step} className="flex items-start gap-3 px-4 py-2.5">
            <StatusGlyph status={ev.status} />
            <div className="flex-1 min-w-0">
              <div
                className={cn(
                  "text-sm",
                  ev.status === "pending"
                    ? "text-neutral-500"
                    : "text-neutral-100",
                )}
              >
                {ev.step}
              </div>
              {ev.detail && (
                <div className="mt-0.5 text-xs text-neutral-500 break-all">
                  {ev.detail}
                </div>
              )}
            </div>
            <div className="text-[10px] text-neutral-600 font-mono">
              {ev.status !== "pending" && fmtRelative(ev.ts)}
            </div>
          </li>
        ))}
      </ul>
      {error && (
        <div className="px-4 py-2 text-xs text-red-300 border-t border-red-900/60">
          sse stream lost — events may be missing. close + reopen to refresh.
        </div>
      )}
    </div>
  );
}

function placeholder(step: string): StepEvent {
  return { step, status: "pending", ts: new Date().toISOString() };
}

function StatusGlyph({ status }: { status: StepEvent["status"] }) {
  if (status === "done") {
    return (
      <div className="mt-0.5 w-4 h-4 rounded-full bg-emerald-500/20 flex items-center justify-center text-emerald-400 text-[11px]">
        ✓
      </div>
    );
  }
  if (status === "running") {
    return (
      <div className="mt-0.5 w-4 h-4 rounded-full border border-amber-400 border-t-transparent animate-spin" />
    );
  }
  if (status === "failed") {
    return (
      <div className="mt-0.5 w-4 h-4 rounded-full bg-red-500/20 flex items-center justify-center text-red-400 text-[11px]">
        ✗
      </div>
    );
  }
  return (
    <div className="mt-0.5 w-4 h-4 rounded-full border border-neutral-700 bg-neutral-900" />
  );
}

function fmtRelative(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  if (ms < 1000) return "just now";
  if (ms < 60_000) return `${Math.round(ms / 1000)}s ago`;
  return `${Math.round(ms / 60_000)}m ago`;
}
