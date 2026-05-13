// /settings/org — config repo url + slack webhook. these are the two
// integration points the eval harness depends on (reasoning-path posts
// to slack, sandbox opens a pr against config_repo_url).

import { createRoute } from "@tanstack/react-router";
import { useOrg, useUpdateOrg } from "@/lib/queries";
import { useEffect, useState } from "react";
import { rootRoute } from "./root";

function SettingsOrgPage() {
  const { data: org, isLoading } = useOrg();
  const update = useUpdateOrg();

  const [configRepoUrl, setConfigRepoUrl] = useState("");
  const [slackWebhookUrl, setSlackWebhookUrl] = useState("");

  useEffect(() => {
    setConfigRepoUrl(org?.config_repo_url ?? "");
    setSlackWebhookUrl(org?.slack_webhook_url ?? "");
  }, [org]);

  return (
    <div className="px-8 py-6 max-w-2xl">
      <h1 className="text-lg font-semibold tracking-tight">org</h1>
      <p className="mt-1 text-sm text-neutral-500">
        where the eval harness opens PRs, and where it posts step updates.
      </p>

      <form
        className="mt-8 space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          update.mutate({
            config_repo_url: configRepoUrl || null,
            slack_webhook_url: slackWebhookUrl || null,
          } as never);
        }}
      >
        <Field
          label="config repo url"
          placeholder="https://github.com/sf-voice/cfg-acme"
          value={configRepoUrl}
          onChange={setConfigRepoUrl}
          disabled={isLoading}
        />
        <Field
          label="slack webhook url"
          placeholder="https://hooks.slack.com/services/..."
          value={slackWebhookUrl}
          onChange={setSlackWebhookUrl}
          disabled={isLoading}
        />

        <div className="flex items-center gap-3 pt-2">
          <button
            type="submit"
            disabled={update.isPending}
            className="rounded-md bg-neutral-100 text-neutral-900 px-3 py-1.5 text-sm font-medium hover:bg-white disabled:opacity-50"
          >
            {update.isPending ? "saving…" : "save"}
          </button>
          {update.isError ? (
            <span className="text-xs text-red-300">
              {(update.error as Error).message}
            </span>
          ) : update.isSuccess ? (
            <span className="text-xs text-neutral-500">saved.</span>
          ) : null}
        </div>
      </form>
    </div>
  );
}

function Field({
  label,
  placeholder,
  value,
  onChange,
  disabled,
}: {
  label: string;
  placeholder?: string;
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <div className="text-xs text-neutral-400">{label}</div>
      <input
        type="text"
        value={value}
        placeholder={placeholder}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-md border border-neutral-800 bg-neutral-950 px-3 py-1.5 text-sm font-mono text-neutral-100 placeholder:text-neutral-700 focus:outline-none focus:ring-1 focus:ring-neutral-500"
      />
    </label>
  );
}

export const settingsOrgRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/settings/org",
  component: SettingsOrgPage,
});
