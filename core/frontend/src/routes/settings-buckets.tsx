// /settings/buckets — s3 input form. v1: UI wired, persistence works,
// but reads still come from internal/test buckets in the backend. real
// customer-bucket auth is v2.

import { createRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useOrg, useUpdateOrg } from "@/lib/queries";
import type { Org } from "@/lib/api";
import { MonoField } from "@/components/ui/MonoField";
import { authedLayoutRoute } from "./_authed";

function SettingsBucketsPage() {
  const { data: org, isLoading } = useOrg();

  return (
    <div className="px-8 py-6 max-w-2xl">
      <h1 className="text-lg font-semibold tracking-tight">buckets</h1>
      <p className="mt-1 text-sm text-neutral-500">
        where your call recordings live. v1 reads from internal test
        buckets; this form persists but the values aren't used until v2.
      </p>

      {/* key remounts the form once org loads (and on org switch), so we
          can seed useState from `org` directly instead of mirroring via
          useEffect — derived state belongs in render, not in effects. */}
      <BucketsForm key={org?.id ?? "loading"} org={org} isLoading={isLoading} />
    </div>
  );
}

function BucketsForm({ org, isLoading }: { org: Org | null | undefined; isLoading: boolean }) {
  const update = useUpdateOrg();
  const [bucketName, setBucketName] = useState(org?.bucket_name ?? "");
  const [bucketPrefix, setBucketPrefix] = useState(org?.bucket_prefix ?? "");
  const [bucketRegion, setBucketRegion] = useState(org?.bucket_region ?? "");

  // lock during the initial load (no org yet) and during a save in
  // flight (avoid edits racing with the response).
  const busy = isLoading || update.isPending;

  return (
    <form
      className="mt-8 space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        update.mutate({
          bucket_name: bucketName || null,
          bucket_prefix: bucketPrefix || null,
          bucket_region: bucketRegion || null,
        });
      }}
    >
      <MonoField
        label="bucket name"
        placeholder="my-voice-recordings"
        value={bucketName}
        onChange={setBucketName}
        disabled={busy}
      />
      <MonoField
        label="prefix"
        placeholder="calls/2026/"
        value={bucketPrefix}
        onChange={setBucketPrefix}
        disabled={busy}
      />
      <MonoField
        label="region"
        placeholder="us-west-2"
        value={bucketRegion}
        onChange={setBucketRegion}
        disabled={busy}
      />

      <div className="flex items-center gap-3 pt-2">
        <button
          type="submit"
          disabled={busy}
          className="rounded-md bg-neutral-100 text-neutral-900 px-3 py-1.5 text-sm font-medium hover:bg-white disabled:opacity-50"
        >
          {update.isPending ? "saving…" : "save"}
        </button>
        {update.isError && (
          <span className="text-xs text-red-300">{update.error.message}</span>
        )}
        {update.isSuccess && (
          <span className="text-xs text-neutral-500">saved.</span>
        )}
      </div>
    </form>
  );
}

export const settingsBucketsRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/settings/buckets",
  component: SettingsBucketsPage,
});
