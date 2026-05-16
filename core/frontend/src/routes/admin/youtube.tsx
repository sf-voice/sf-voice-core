// /admin/_internal/youtube — admin tooling page. lives under the authed
// layout so it shares the sidebar + sign-in/out chrome and inherits the
// 401 redirect-to-login from the layout's auth gate.
//
// data model: each ingest creates one parent doc (raw.mp4 + the youtube
// url) and three derived docs (video.mp4, audio.m4a, audio.wav) pointing
// at the parent via source_id. detail endpoint returns both.

import { createRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { authedLayoutRoute } from "../_authed";

const API_BASE_URL = "http://localhost:8080";

type StepEvent = {
   step: string;
   status: "pending" | "running" | "done" | "failed";
   ts: string;
   detail?: string;
};

// matches DocumentRow on the backend. `type` is reserved-ish in TS, but
// fine as a property name. processing_status walks: queued → downloading
// → extracting → uploading → ready / failed.
type DocumentRow = {
   id: string;
   type: "internal" | "customer";
   media_kind: "audio" | "video";
   source_kind: string;
   source_id: string | null;
   source_url: string | null;
   bucket: string | null;
   s3_key: string | null;
   filename: string | null;
   mime_type: string | null;
   duration_ms: number | null;
   processing_status:
      | "queued"
      | "downloading"
      | "extracting"
      | "uploading"
      | "ready"
      | "failed";
   processing_error: string | null;
   job_id: string | null;
   title: string | null;
   created_at: string;
   updated_at: string;
   progress_steps: StepEvent[] | null;
};

// what GET /api/_internal/documents/:id returns. parent row's fields are
// flattened at the top level by the backend; `derived` is the children.
type DocumentDetail = DocumentRow & {
   derived: DocumentRow[];
};

type CreateResponse = {
   document_id: string;
   job_id: string | null;
   existing: boolean;
};

async function api<T>(
   path: string,
   init?: RequestInit & { json?: unknown },
): Promise<T> {
   const headers = new Headers(init?.headers);
   if (init?.json !== undefined) headers.set("content-type", "application/json");

   const res = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      credentials: "include",
      headers,
      body: init?.json !== undefined ? JSON.stringify(init.json) : init?.body,
   });
   if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(text || `${res.status} ${res.statusText}`);
   }
   if (res.status === 204) return null as T;
   return (await res.json()) as T;
}

// pull the step name that died from progress_steps. priority: an
// explicit `status==='failed'` event wins; otherwise the last `running`
// event we saw is what was in-flight when the job blew up. used to
// label the retry button so the user knows what they're retrying.
function failedStepName(events: StepEvent[] | null | undefined): string | null {
   if (!events || events.length === 0) return null;
   const explicit = [...events].reverse().find((e) => e.status === "failed");
   if (explicit && explicit.step !== "job failed") return explicit.step;
   const running = [...events].reverse().find((e) => e.status === "running");
   return running?.step ?? null;
}

function InternalYoutubePage() {
   const [url, setUrl] = useState("");
   const [submitting, setSubmitting] = useState(false);
   const [submitError, setSubmitError] = useState<string | null>(null);
   const [active, setActive] = useState<DocumentDetail | null>(null);
   const [recent, setRecent] = useState<DocumentRow[]>([]);
   // id of the row currently being retried/re-ingested. used to disable
   // the per-row buttons so a double-click can't enqueue twice.
   const [retrying, setRetrying] = useState<string | null>(null);

   // refresh recent list on mount + whenever the active job transitions.
   useEffect(() => {
      let cancelled = false;
      api<DocumentRow[]>("/api/_internal/documents")
         .then((rows) => {
            if (!cancelled) setRecent(rows);
         })
         .catch(() => {/* not logged in or transient — leave empty */});
      return () => {
         cancelled = true;
      };
   }, [active?.processing_status]);

   // live progress via SSE on the active job. opens when the doc is
   // in-flight (queued/downloading/extracting/uploading) and a job_id
   // is set. step events arrive as they happen; on a terminal step
   // (or stream close) we re-fetch the doc detail to pick up
   // processing_status + the derived rows the backend inserted.
   useEffect(() => {
      if (!active?.job_id) return;
      if (active.processing_status === "ready" || active.processing_status === "failed") return;

      const currentId = active.id;
      const currentJobId = active.job_id;

      const es = new EventSource(
         `${API_BASE_URL}/api/_internal/jobs/${currentJobId}/events`,
         { withCredentials: true },
      );

      // SSE replays existing events on connect. the first message marks
      // the start of that replay — wipe our locally-cached progress_steps
      // and rebuild from SSE so we don't double-count.
      let firstMessage = true;

      const refetchDetail = () => {
         api<DocumentDetail | null>(`/api/_internal/documents/${currentId}`)
            .then((detail) => {
               if (detail) setActive(detail);
            })
            .catch(() => {/* ignore */});
      };

      const onStep = (e: MessageEvent) => {
         try {
            const event: StepEvent = JSON.parse(e.data);
            const wasFirst = firstMessage;
            firstMessage = false;
            setActive((prev) => {
               if (!prev || prev.id !== currentId) return prev;
               const steps = wasFirst
                  ? [event]
                  : [...(prev.progress_steps ?? []), event];
               return { ...prev, progress_steps: steps };
            });
            // terminal step (`ready` done OR any `failed`) → re-fetch
            // detail to pick up the row's new status + derived rows.
            if (
               event.status === "failed" ||
               (event.status === "done" && event.step === "ready")
            ) {
               refetchDetail();
            }
         } catch {/* malformed event */}
      };

      es.addEventListener("step.done", onStep);
      es.addEventListener("step.running", onStep);
      es.addEventListener("step.failed", onStep);
      es.addEventListener("step.pending", onStep);

      // server closes the stream when the job finishes (broker.close);
      // EventSource will try to auto-reconnect, so we close + refetch
      // ourselves to settle the final state cleanly.
      es.addEventListener("error", () => {
         es.close();
         refetchDetail();
      });

      return () => {
         es.close();
      };
   }, [active?.id, active?.job_id, active?.processing_status]);

   async function onSubmit(e: React.FormEvent) {
      e.preventDefault();
      setSubmitError(null);
      setSubmitting(true);
      try {
         const res = await api<CreateResponse>("/api/_internal/youtube", {
            method: "POST",
            json: { url: url.trim() },
         });
         const detail = await api<DocumentDetail | null>(
            `/api/_internal/documents/${res.document_id}`,
         );
         if (detail) setActive(detail);
         setUrl("");
      } catch (err) {
         setSubmitError(err instanceof Error ? err.message : String(err));
      } finally {
         setSubmitting(false);
      }
   }

   // force=true on the backend: deletes the existing derived rows,
   // resets the parent doc to 'queued', and enqueues a fresh job.
   // used for 'ready' rows that want a full re-download from scratch.
   async function onForceReingest(row: DocumentRow) {
      if (!row.source_url) return;
      setRetrying(row.id);
      try {
         const res = await api<CreateResponse>("/api/_internal/youtube", {
            method: "POST",
            json: { url: row.source_url, force: true },
         });
         const detail = await api<DocumentDetail | null>(
            `/api/_internal/documents/${res.document_id}`,
         );
         if (detail) setActive(detail);
      } catch (err) {
         setSubmitError(err instanceof Error ? err.message : String(err));
      } finally {
         setRetrying(null);
      }
   }

   // soft retry — re-enqueues an ingest job against the existing failed
   // document. preserves work_dir intermediate files on the worker and
   // already-uploaded s3 objects, so the job resumes at whichever step
   // died. ONLY valid when processing_status === 'failed'.
   async function onRetry(row: DocumentRow) {
      setRetrying(row.id);
      try {
         await api<CreateResponse>(`/api/_internal/documents/${row.id}/retry`, {
            method: "POST",
         });
         const detail = await api<DocumentDetail | null>(
            `/api/_internal/documents/${row.id}`,
         );
         if (detail) setActive(detail);
      } catch (err) {
         setSubmitError(err instanceof Error ? err.message : String(err));
      } finally {
         setRetrying(null);
      }
   }

   return (
      <div className="mx-auto max-w-3xl px-6 py-10 font-sans text-sm text-zinc-200">
         <h1 className="text-lg font-semibold tracking-tight text-zinc-100">
            Internal · YouTube ingest
         </h1>
         <p className="mt-1 text-xs text-zinc-500">
            Not a customer surface. Saves raw + audio (m4a, wav) + video to the
            sf-voice internal bucket as `documents` rows for later bulk
            processing.
         </p>

         <form
            onSubmit={onSubmit}
            className="mt-6 rounded border border-zinc-800 bg-zinc-950 p-4"
         >
            <label className="block text-xs font-medium text-zinc-400">
               YouTube URL
            </label>
            <div className="mt-1 flex gap-2">
               <input
                  type="url"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  placeholder="https://www.youtube.com/watch?v=..."
                  required
                  className="flex-1 rounded border border-zinc-800 bg-black px-3 py-2 font-mono text-xs text-zinc-100 outline-none focus:border-zinc-600"
               />
               <button
                  type="submit"
                  disabled={!url || submitting}
                  className="rounded bg-zinc-100 px-4 py-2 text-xs font-medium text-zinc-900 disabled:cursor-not-allowed disabled:bg-zinc-800 disabled:text-zinc-500"
               >
                  {submitting ? "Submitting…" : "Ingest"}
               </button>
            </div>
            {submitError && (
               <div className="mt-2 rounded border border-red-900 bg-red-950 px-3 py-2 text-xs text-red-300">
                  {submitError}
               </div>
            )}
         </form>

         {active && (
            <section className="mt-4 rounded border border-zinc-800 bg-zinc-950 p-4">
               <div className="flex items-center justify-between">
                  <div className="font-mono text-xs text-zinc-500">
                     {active.id}
                  </div>
                  <div className="flex items-center gap-2">
                     <StatusBadge row={active} />
                     {active.processing_status === "failed" && (() => {
                        const step = failedStepName(active.progress_steps);
                        const label = step ? `Retry: ${step}` : "Retry";
                        return (
                           <button
                              type="button"
                              disabled={retrying === active.id}
                              onClick={() => onRetry(active)}
                              title={step
                                 ? `Resume from "${step}" — keeps already-completed work`
                                 : "Soft retry — resumes from where the job failed"}
                              className="rounded border border-amber-900 bg-amber-950/40 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-amber-300 hover:border-amber-700 hover:text-amber-200 disabled:opacity-50"
                           >
                              {retrying === active.id ? "…" : label}
                           </button>
                        );
                     })()}
                     {(active.processing_status === "failed" ||
                        active.processing_status === "ready") && (
                        <button
                           type="button"
                           disabled={retrying === active.id}
                           onClick={() => onForceReingest(active)}
                           title="Re-ingest from scratch — deletes derived rows + redownloads"
                           className="rounded border border-zinc-800 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-zinc-400 hover:border-zinc-700 hover:text-zinc-200 disabled:opacity-50"
                        >
                           {retrying === active.id ? "…" : "Re-ingest"}
                        </button>
                     )}
                  </div>
               </div>
               <div className="mt-2 text-sm text-zinc-200">
                  {active.title ?? "(no title yet)"}
               </div>
               <div className="mt-1 truncate font-mono text-[11px] text-zinc-500">
                  {active.source_url}
               </div>
               {active.processing_error && (
                  <div className="mt-2 rounded border border-red-900 bg-red-950 px-3 py-2 font-mono text-[11px] text-red-300">
                     {active.processing_error}
                  </div>
               )}
               {active.progress_steps && active.progress_steps.length > 0 && (
                  <Timeline events={active.progress_steps} />
               )}
               {active.processing_status === "ready" && active.derived.length > 0 && (
                  <DerivedList parent={active} derived={active.derived} />
               )}
            </section>
         )}

         {recent.length > 0 && (
            <section className="mt-6">
               <h2 className="text-xs font-medium uppercase tracking-wider text-zinc-500">
                  Recent
               </h2>
               <ul className="mt-2 divide-y divide-zinc-900 rounded border border-zinc-800 bg-zinc-950">
                  {recent.map((row) => {
                     const terminal =
                        row.processing_status === "ready" ||
                        row.processing_status === "failed";
                     return (
                        <li
                           key={row.id}
                           className="cursor-pointer px-4 py-2 hover:bg-zinc-900"
                           onClick={async () => {
                              // fetch the detail (with derived) before
                              // setting active — otherwise the active card
                              // would render with an empty derived list.
                              try {
                                 const detail = await api<DocumentDetail | null>(
                                    `/api/_internal/documents/${row.id}`,
                                 );
                                 if (detail) setActive(detail);
                              } catch {/* ignore */}
                           }}
                        >
                           <div className="flex items-center justify-between gap-3">
                              <div className="truncate text-sm text-zinc-200">
                                 {row.title ?? row.source_url}
                              </div>
                              <div className="flex items-center gap-2 shrink-0">
                                 <StatusBadge row={row} />
                                 {row.processing_status === "failed" && (() => {
                                    const step = failedStepName(row.progress_steps);
                                    const label = step ? `Retry: ${step}` : "Retry";
                                    return (
                                       <button
                                          type="button"
                                          disabled={retrying === row.id}
                                          onClick={(e) => {
                                             e.stopPropagation();
                                             onRetry(row);
                                          }}
                                          title={step
                                             ? `Resume from "${step}" — keeps already-completed work`
                                             : "Soft retry — resumes from where the job failed"}
                                          className="rounded border border-amber-900 bg-amber-950/40 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-amber-300 hover:border-amber-700 hover:text-amber-200 disabled:opacity-50"
                                       >
                                          {retrying === row.id ? "…" : label}
                                       </button>
                                    );
                                 })()}
                                 {terminal && (
                                    <button
                                       type="button"
                                       disabled={retrying === row.id}
                                       onClick={(e) => {
                                          // stop the row's onClick so the
                                          // active card doesn't flicker
                                          // while we re-enqueue.
                                          e.stopPropagation();
                                          onForceReingest(row);
                                       }}
                                       title="Re-ingest from scratch — deletes derived rows + redownloads"
                                       className="rounded border border-zinc-800 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-zinc-400 hover:border-zinc-700 hover:text-zinc-200 disabled:opacity-50"
                                    >
                                       {retrying === row.id ? "…" : "Re-ingest"}
                                    </button>
                                 )}
                              </div>
                           </div>
                           <div className="mt-1 truncate font-mono text-[11px] text-zinc-500">
                              {row.source_url}
                           </div>
                        </li>
                     );
                  })}
               </ul>
            </section>
         )}
      </div>
   );
}

// derive the badge label. terminal states show themselves; in-progress
// shows the most recently running step from progress_steps so the user
// sees "extracting audio" instead of the coarser "downloading" that the
// row column reports during ffmpeg/upload phases.
function badgeLabel(row: DocumentRow): string {
   if (row.processing_status === "ready" || row.processing_status === "failed") {
      return row.processing_status;
   }
   const events = row.progress_steps ?? [];
   const lastRunning = [...events].reverse().find((e) => e.status === "running");
   return lastRunning?.step ?? row.processing_status;
}

function StatusBadge({ row }: { row: DocumentRow }) {
   const tone =
      row.processing_status === "ready"
         ? "border-emerald-800 bg-emerald-950 text-emerald-300"
         : row.processing_status === "failed"
            ? "border-red-900 bg-red-950 text-red-300"
            : "border-zinc-700 bg-zinc-900 text-zinc-300";
   return (
      <span
         className={`rounded border px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider ${tone}`}
      >
         {badgeLabel(row)}
      </span>
   );
}

type CollapsedStep = {
   step: string;
   status: StepEvent["status"];
   start_ts: string;
   end_ts?: string;
   detail?: string;
};

function collapseSteps(events: StepEvent[]): CollapsedStep[] {
   const order: string[] = [];
   const map = new Map<string, CollapsedStep>();
   for (const ev of events) {
      const existing = map.get(ev.step);
      if (!existing) {
         order.push(ev.step);
         map.set(ev.step, {
            step: ev.step,
            status: ev.status,
            start_ts: ev.ts,
            detail: ev.detail,
            end_ts: ev.status === "running" ? undefined : ev.ts,
         });
      } else {
         existing.status = ev.status;
         if (ev.status === "done" || ev.status === "failed") {
            existing.end_ts = ev.ts;
         }
         if (ev.detail) existing.detail = ev.detail;
      }
   }
   return order.map((s) => map.get(s)!);
}

function formatDuration(ms: number): string {
   if (ms < 1000) return `${ms}ms`;
   const s = ms / 1000;
   if (s < 60) return `${s.toFixed(1)}s`;
   const m = Math.floor(s / 60);
   const rem = Math.round(s - m * 60);
   return `${m}m ${rem}s`;
}

function Timeline({ events }: { events: StepEvent[] }) {
   const steps = collapseSteps(events);
   const now = Date.now();
   return (
      <ol className="mt-3 space-y-1.5">
         {steps.map((s) => {
            const start = Date.parse(s.start_ts);
            const end = s.end_ts ? Date.parse(s.end_ts) : now;
            const elapsed = Math.max(0, end - start);
            const glyph =
               s.status === "done"
                  ? "✓"
                  : s.status === "failed"
                     ? "✕"
                     : s.status === "running"
                        ? "⟳"
                        : "·";
            const tone =
               s.status === "done"
                  ? "text-emerald-400"
                  : s.status === "failed"
                     ? "text-red-400"
                     : s.status === "running"
                        ? "text-zinc-300"
                        : "text-zinc-600";
            return (
               <li key={s.step} className="flex items-start gap-3 text-[12px]">
                  <span className={`w-4 shrink-0 text-center font-mono ${tone}`}>
                     {glyph}
                  </span>
                  <div className="flex-1 min-w-0">
                     <div className="flex items-baseline justify-between gap-3">
                        <span
                           className={
                              s.status === "running"
                                 ? "text-zinc-200"
                                 : "text-zinc-400"
                           }
                        >
                           {s.step}
                        </span>
                        <span className="font-mono text-[10px] text-zinc-600 shrink-0">
                           {formatDuration(elapsed)}
                           {!s.end_ts && s.status === "running" && " …"}
                        </span>
                     </div>
                     {s.detail && (
                        <div className="mt-0.5 truncate font-mono text-[10px] text-zinc-500">
                           {s.detail}
                        </div>
                     )}
                  </div>
               </li>
            );
         })}
      </ol>
   );
}

// renders the parent + its derived docs as a flat list of playable s3
// URIs. the parent is included so the raw mp4 is reachable from the same
// surface.
function DerivedList({
   parent,
   derived,
}: {
   parent: DocumentRow;
   derived: DocumentRow[];
}) {
   const rows = [parent, ...derived];
   return (
      <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 font-mono text-[11px]">
         {rows.map((r) => (
            <UriRow
               key={r.id}
               label={r.filename ?? r.media_kind}
               value={
                  r.bucket && r.s3_key ? `s3://${r.bucket}/${r.s3_key}` : null
               }
            />
         ))}
      </dl>
   );
}

function UriRow({ label, value }: { label: string; value: string | null }) {
   return (
      <>
         <dt className="text-zinc-500">{label}</dt>
         <dd className="truncate text-zinc-300">{value ?? "—"}</dd>
      </>
   );
}

export const internalYoutubeRoute = createRoute({
   getParentRoute: () => authedLayoutRoute,
   path: "/admin/_internal/youtube",
   component: InternalYoutubePage,
});
