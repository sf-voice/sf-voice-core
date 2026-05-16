// /settings/billing — placeholder. real plan-management lives behind
// stripe (or whatever billing provider lands), not yet wired. for v1
// this page just renders the shape of what the customer will see so the
// nav entry isn't a dead link.

import { createRoute } from "@tanstack/react-router";
import { useOrg } from "@/lib/queries";
import { authedLayoutRoute } from "./_authed";

function SettingsBillingPage() {
  const { data: org } = useOrg();

  return (
    <div className="px-8 py-6 max-w-3xl">
      <h1 className="text-lg font-semibold tracking-tight">Billing</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Plan, usage, and invoices for {org?.name ?? "this org"}.
      </p>

      <section className="mt-8 rounded-md border border-border bg-muted/10 p-6">
        <div className="flex items-baseline gap-3">
          <div className="text-2xl font-semibold tracking-tight">Free</div>
          <div className="text-sm text-muted-foreground">Dev / pilot tier</div>
        </div>
        <p className="mt-2 text-sm text-muted-foreground">
          Paid plans go live alongside the public beta. We'll email everyone
          on the pilot when pricing is announced; nothing you do here today
          will switch off without notice.
        </p>
      </section>

      <section className="mt-8 space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
          This billing cycle
        </h2>
        <div className="grid grid-cols-3 gap-3">
          <UsageCard label="Calls ingested" value="—" />
          <UsageCard label="Minutes transcribed" value="—" />
          <UsageCard label="Slices analysed" value="—" />
        </div>
        <p className="text-sm text-muted-foreground">
          Usage tracking flips on with the paid-plans launch.
        </p>
      </section>
    </div>
  );
}

function UsageCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-border bg-muted/10 px-4 py-3">
      <div className="text-xs uppercase tracking-wider text-muted-foreground">
        {label}
      </div>
      <div className="mt-1 text-lg font-semibold tracking-tight">{value}</div>
    </div>
  );
}

export const settingsBillingRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/settings/billing",
  component: SettingsBillingPage,
});
