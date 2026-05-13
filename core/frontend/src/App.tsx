// sf-voice frontend — app.sf-voice.sh
// dev: http://localhost:5173 (via `mise run core:dev`)
import { useEffect, useState } from "react";
import { getHello, type Hello } from "@/lib/api";

type ApiState =
  | { kind: "loading" }
  | { kind: "ok"; data: Hello }
  | { kind: "error"; message: string };

export function App() {
  const [state, setState] = useState<ApiState>({ kind: "loading" });

  // single fire on mount — replace with react-query / swr once we have
  // more than one endpoint to manage.
  useEffect(() => {
    let cancelled = false;
    getHello()
      .then((data) => {
        if (!cancelled) setState({ kind: "ok", data });
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setState({
            kind: "error",
            message: err instanceof Error ? err.message : String(err),
          });
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-950 text-neutral-50 font-medium px-6">
      <div className="text-center max-w-md">
        <h1 className="text-3xl font-semibold tracking-tight">sf-voice</h1>
        <p className="mt-2 text-neutral-400">app.sf-voice.sh — scaffold</p>

        <section className="mt-8 rounded-xl border border-neutral-800 bg-neutral-900 p-5 text-left">
          <h2 className="text-sm uppercase tracking-wider text-neutral-400">
            api.sf-voice.sh
          </h2>
          <ApiStateView state={state} />
        </section>
      </div>
    </main>
  );
}

function ApiStateView({ state }: { state: ApiState }) {
  if (state.kind === "loading") {
    return <p className="mt-3 text-neutral-300">calling /api/hello…</p>;
  }
  if (state.kind === "error") {
    return (
      <p className="mt-3 text-red-400">
        error: {state.message}
        <br />
        <span className="text-neutral-500 text-sm">
          is the api running? try <code>mise run core:dev</code> or{" "}
          <code>cargo run -p sf-voice-api</code>.
        </span>
      </p>
    );
  }
  return (
    <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
      <dt className="text-neutral-500">service</dt>
      <dd className="font-mono">{state.data.service}</dd>
      <dt className="text-neutral-500">version</dt>
      <dd className="font-mono">{state.data.version}</dd>
      <dt className="text-neutral-500">message</dt>
      <dd>{state.data.message}</dd>
    </dl>
  );
}
