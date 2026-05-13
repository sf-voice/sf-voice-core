// A/B audio player. two <audio> elements side-by-side. for v1 the
// regenerated audio is a placeholder — the sandbox-stub doesn't produce
// real TTS. shown alongside the PR URL when the reasoning path completes.

import { cn } from "@/lib/utils";

type Props = {
  originalUrl: string | null;
  regeneratedUrl: string | null;
  prUrl?: string | null;
};

export function ABPlayer({ originalUrl, regeneratedUrl, prUrl }: Props) {
  return (
    <div className="rounded-lg border border-neutral-900 bg-neutral-950 p-4 space-y-3">
      <div className="flex items-baseline justify-between">
        <h3 className="text-sm font-semibold text-neutral-100">A / B audio</h3>
        {prUrl && (
          <a
            href={prUrl}
            target="_blank"
            rel="noreferrer"
            className="text-xs text-emerald-300 hover:text-emerald-200 underline-offset-4 hover:underline"
          >
            open PR ↗
          </a>
        )}
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Side label="original" url={originalUrl} tone="caller" />
        <Side label="regenerated (stub)" url={regeneratedUrl} tone="ai" />
      </div>
    </div>
  );
}

function Side({
  label,
  url,
  tone,
}: {
  label: string;
  url: string | null;
  tone: "caller" | "ai";
}) {
  return (
    <div
      className={cn(
        "rounded-md border p-2",
        tone === "ai"
          ? "border-emerald-500/30 bg-emerald-500/5"
          : "border-sky-500/30 bg-sky-500/5",
      )}
    >
      <div className="text-[11px] uppercase tracking-wider text-neutral-400 mb-1">
        {label}
      </div>
      {url ? (
        <audio controls src={url} className="w-full" />
      ) : (
        <div className="text-xs text-neutral-600 py-3">
          no audio (real sandbox lands post-demo — see core/TODO.md)
        </div>
      )}
    </div>
  );
}
