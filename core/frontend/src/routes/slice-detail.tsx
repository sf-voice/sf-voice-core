// /calls/$callId/slices/$sliceId — prompt-on-slice page. phase G fills
// this in with the reasoning-path panel + A/B audio.

import { Link, createRoute } from "@tanstack/react-router";
import { useSlice } from "@/lib/queries";
import { rootRoute } from "./root";

function SliceDetailPage() {
  const { callId, sliceId } = sliceDetailRoute.useParams();
  const { data: slice, isLoading } = useSlice(sliceId);

  return (
    <div className="px-8 py-6">
      <Link
        to="/calls/$callId"
        params={{ callId }}
        className="text-sm text-neutral-400 hover:text-neutral-100"
      >
        ← back to call
      </Link>
      <h1 className="mt-4 text-lg font-semibold tracking-tight">
        slice <span className="font-mono">{sliceId}</span>
      </h1>
      <section className="mt-8 rounded-lg border border-dashed border-neutral-800 px-6 py-12 text-center">
        <h3 className="text-sm font-medium text-neutral-200">
          reasoning path + A/B audio coming in phase G
        </h3>
        <p className="mt-1 text-sm text-neutral-500">
          {isLoading
            ? "loading slice…"
            : slice
              ? `status: ${slice.status}`
              : "slice not found — backend stubs return null in v1 phase E."}
        </p>
      </section>
    </div>
  );
}

export const sliceDetailRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/calls/$callId/slices/$sliceId",
  component: SliceDetailPage,
});
