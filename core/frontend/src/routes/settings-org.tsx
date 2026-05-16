// /settings/org — config repo url + slack webhook. these are the two
// integration points the eval harness depends on (reasoning-path posts
// to slack, sandbox opens a pr against config_repo_url).

import { createRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useOrg, useUpdateOrg } from "@/lib/queries";
import type { Org } from "@/lib/api";
import { MonoField } from "@/components/ui/MonoField";
import { authedLayoutRoute } from "./_authed";

function SettingsOrgPage() {
  const { data: org, isLoading } = useOrg();

  return (
    <div className="px-8 py-6 max-w-2xl">
      <h1 className="text-lg font-semibold tracking-tight">org</h1>
      <p className="mt-1 text-sm text-neutral-500">
        where the eval harness opens PRs, and where it posts step updates.
      </p>

      {/* key remounts the form once org loads (and on org switch). lets
          us seed useState from `org` in render rather than mirroring it
          through useEffect. */}
      <OrgForm key={org?.id ?? "loading"} org={org} isLoading={isLoading} />
    </div>
  );
}

function OrgForm({ org, isLoading }: { org: Org | null | undefined; isLoading: boolean }) {
  const update = useUpdateOrg();
  const [configRepoUrl, setConfigRepoUrl] = useState(org?.config_repo_url ?? "");
  const [slackWebhookUrl, setSlackWebhookUrl] = useState(org?.slack_webhook_url ?? "");

  const busy = isLoading || update.isPending;

  return (
    <form
      className="mt-8 space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        update.mutate({
          config_repo_url: configRepoUrl || null,
          slack_webhook_url: slackWebhookUrl || null,
        });
      }}
    >
      <MonoField
        label="config repo url"
        placeholder="https://github.com/sf-voice/cfg-acme"
        value={configRepoUrl}
        onChange={setConfigRepoUrl}
        disabled={busy}
      />
      <MonoField
        label="slack webhook url"
        placeholder="https://hooks.slack.com/services/..."
        value={slackWebhookUrl}
        onChange={setSlackWebhookUrl}
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

export const settingsOrgRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/settings/org",
  component: SettingsOrgPage,
});
