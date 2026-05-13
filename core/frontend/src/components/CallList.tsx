// sentry-style call table. v1: minimal columns, no filters yet.
// filters land alongside ingest in phase C.

import { Link } from "@tanstack/react-router";
import { formatDistanceToNow } from "date-fns";
import type { Call } from "@/lib/api";

function fmtDuration(ms: number | null) {
  if (ms == null) return "—";
  const s = Math.round(ms / 1000);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m${r.toString().padStart(2, "0")}s` : `${r}s`;
}

export function CallList({ calls }: { calls: Call[] }) {
  if (calls.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-neutral-800 px-6 py-12 text-center">
        <h3 className="text-sm font-medium text-neutral-200">
          no calls yet
        </h3>
        <p className="mt-1 text-sm text-neutral-500">
          drop a recording into the configured s3 bucket, then run ingest.
          configure the bucket under{" "}
          <Link
            to="/settings/buckets"
            className="text-neutral-300 underline underline-offset-4 hover:text-neutral-100"
          >
            settings / buckets
          </Link>
          .
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-neutral-900 overflow-hidden">
      <table className="w-full text-sm">
        <thead className="bg-neutral-900/50 text-neutral-400 text-left">
          <tr>
            <th className="px-4 py-2 font-medium">started</th>
            <th className="px-4 py-2 font-medium">caller</th>
            <th className="px-4 py-2 font-medium">duration</th>
            <th className="px-4 py-2 font-medium">termination</th>
            <th className="px-4 py-2 font-medium" aria-label="open" />
          </tr>
        </thead>
        <tbody>
          {calls.map((c) => (
            <tr
              key={c.id}
              className="border-t border-neutral-900 hover:bg-neutral-900/40 relative"
            >
              <td className="px-4 py-2 text-neutral-300">
                {formatDistanceToNow(new Date(c.started_at), {
                  addSuffix: true,
                })}
              </td>
              <td className="px-4 py-2 font-mono text-xs text-neutral-300">
                {c.caller_number ?? "unknown"}
              </td>
              <td className="px-4 py-2 text-neutral-400">
                {fmtDuration(c.duration_ms)}
              </td>
              <td className="px-4 py-2 text-neutral-400">
                {c.termination_reason ?? "—"}
              </td>
              <td className="px-4 py-2">
                <Link
                  to="/calls/$callId"
                  params={{ callId: c.id }}
                  className="absolute inset-0"
                  aria-label={`open call ${c.id}`}
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
