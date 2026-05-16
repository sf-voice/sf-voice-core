// /create-org — single-field landing for users who are authed but have
// no current org (fresh signup without org_name, or kicked out of every
// org). _authed.tsx redirects here when me.org is null. submitting
// creates an org via POST /api/orgs, flips current_org_id, and lands
// the user back on /.

import { useState } from "react";
import { createRoute, useNavigate } from "@tanstack/react-router";
import { useCreateOrg, useMe } from "@/lib/queries";
import { ApiError } from "@/lib/api";
import { authedLayoutRoute } from "./_authed";

function CreateOrgPage() {
  const navigate = useNavigate();
  const { data: me } = useMe();
  const createOrg = useCreateOrg();
  const [name, setName] = useState("");

  return (
    <div className="mx-auto w-full max-w-md py-16">
      <header className="mb-8">
        <h1 className="text-2xl font-medium text-foreground">
          create your org
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          {me?.user.email
            ? `signed in as ${me.user.email}. `
            : ""}
          everything in sf-voice lives inside an org. name it whatever —
          you can change it later in settings.
        </p>
      </header>

      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          if (!name.trim()) return;
          createOrg.mutate(name.trim(), {
            onSuccess: () => navigate({ to: "/" }),
          });
        }}
      >
        <label className="block">
          <span className="text-xs uppercase tracking-wide text-muted-foreground">
            org name
          </span>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
            autoFocus
            placeholder="acme restaurant"
            className="mt-1 w-full rounded-md border border-border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </label>

        <button
          type="submit"
          disabled={createOrg.isPending || !name.trim()}
          className="w-full rounded-md bg-primary text-primary-foreground py-2.5 text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {createOrg.isPending ? "creating…" : "create org"}
        </button>

        {createOrg.isError && (
          <p className="text-xs text-destructive">
            {createOrg.error instanceof ApiError
              ? createOrg.error.message
              : (createOrg.error as Error).message}
          </p>
        )}
      </form>
    </div>
  );
}

export const createOrgRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/create-org",
  component: CreateOrgPage,
});
