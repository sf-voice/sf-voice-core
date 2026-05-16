// /admin — staff console. tile-based directory of internal tooling.
// access is restricted to users whose email matches @sf-voice.sh; the
// backend enforces this on every /api/admin/* call. the route still
// renders for non-staff if they type the URL — they'll just get 403s
// when fetching data. UI-side we keep this minimal because the popover
// entry is already gated.

import { createRoute, Link } from "@tanstack/react-router";
import { useMe } from "@/lib/queries";
import { cn } from "@/lib/utils";
import { authedLayoutRoute } from "../_authed";

const ADMIN_SUFFIX = "@sf-voice.sh";

type Tool = {
  to: string;
  label: string;
  description: string;
  status: "live" | "stub";
};

const tools: Tool[] = [
  {
    to: "/admin/_internal/youtube",
    label: "YouTube ingest",
    description:
      "Bulk-import recordings from a YouTube URL into an internal org for testing.",
    status: "live",
  },
  {
    to: "/admin/orgs",
    label: "All orgs",
    description:
      "Every org in the system: member count, bucket-connected status, last ingest, last call.",
    status: "stub",
  },
  {
    to: "/admin/jobs",
    label: "Job runner",
    description:
      "Live view of the in-process job queue. Filter by status, kind, org. Cancel or retry.",
    status: "stub",
  },
  {
    to: "/admin/users",
    label: "Users",
    description:
      "Every account in the system: orgs, last login, sessions. Spoof via `?spoof=email@domain` (current URL only).",
    status: "stub",
  },
];

function AdminPage() {
  const { data: me } = useMe();
  const isAdmin = me?.user.email.toLowerCase().endsWith(ADMIN_SUFFIX) ?? false;

  if (!me) return null;

  if (!isAdmin) {
    return (
      <div className="px-10 py-8 max-w-2xl">
        <h1 className="text-lg font-semibold tracking-tight">Admin</h1>
        <div className="mt-6 rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm">
          <div className="font-medium text-destructive">Not authorized.</div>
          <p className="mt-1 text-muted-foreground">
            This area is restricted to sf-voice staff.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="px-10 py-8 max-w-4xl">
      <header className="mb-6">
        <h1 className="text-lg font-semibold tracking-tight">Admin</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Internal tooling. Visible only to <code>@sf-voice.sh</code>. Server
          enforces this on every <code>/api/admin/*</code> route.
        </p>
      </header>

      <div className="grid grid-cols-2 gap-3">
        {tools.map((t) => (
          <Link
            key={t.to}
            to={t.to}
            className={cn(
              "block rounded-md border border-border bg-muted/10 px-4 py-4",
              "hover:bg-muted/30 hover:border-foreground/40 transition-colors",
            )}
          >
            <div className="flex items-baseline justify-between gap-2">
              <div className="text-sm font-semibold">{t.label}</div>
              <StatusPill status={t.status} />
            </div>
            <p className="mt-1 text-xs text-muted-foreground">
              {t.description}
            </p>
          </Link>
        ))}
      </div>

      <section className="mt-10">
        <h2 className="text-sm font-semibold tracking-tight">Spoofing</h2>
        <p className="mt-1 text-xs text-muted-foreground max-w-xl">
          Append <code>?spoof=&lt;email&gt;</code> to any product URL to view
          it as that user. Clear the query string to stop spoofing. Spoofing
          requires staff; every spoof event is logged.
        </p>
      </section>
    </div>
  );
}

function StatusPill({ status }: { status: Tool["status"] }) {
  if (status === "live") {
    return (
      <span className="text-[10px] uppercase tracking-wider text-success">
        Live
      </span>
    );
  }
  return (
    <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
      Stub
    </span>
  );
}

export const adminRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/admin",
  component: AdminPage,
});
