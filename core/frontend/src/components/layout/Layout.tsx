// shell for authenticated product surfaces. dark theme wrapper; the
// auth gate lives in routes/_authed.tsx. shows side nav + account menu.

import { Link } from "@tanstack/react-router";
import { type ReactNode, useState } from "react";
import { cn } from "@/lib/utils";
import { useLogout, useMyOrgs, useSwitchOrg } from "@/lib/queries";
import type { Me } from "@/lib/api";
import { useNavigate } from "@tanstack/react-router";

const navItems = [
  { to: "/", label: "Calls" },
  { to: "/settings/buckets", label: "Buckets" },
  { to: "/settings/org", label: "Org" },
] as const;

type Props = {
  me: Me;
  children: ReactNode;
};

export function Layout({ me, children }: Props) {
  return (
    <div className="theme-dark min-h-screen bg-background text-foreground flex">
      <aside className="w-56 shrink-0 border-r border-border px-4 py-6 flex flex-col gap-6">
        <OrgSwitcher me={me} />
        <nav className="flex flex-col gap-1 text-sm">
          {navItems.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              activeOptions={{ exact: item.to === "/" }}
              className={cn(
                "px-3 py-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/40",
              )}
              activeProps={{
                className: "bg-muted/60 text-foreground",
              }}
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="mt-auto">
          <AccountMenu me={me} />
        </div>
      </aside>
      <main className="flex-1 min-w-0">{children}</main>
    </div>
  );
}

// org banner + dropdown at the top of the sidebar. shows the current
// org and lets the user switch between memberships or create a new one.
// `useMyOrgs` only fetches when the popover is opened — the trigger
// itself runs off `me.org` (already in cache).
function OrgSwitcher({ me }: { me: Me }) {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  // me.org is non-null inside Layout — the orgless branch in _authed.tsx
  // bypasses Layout entirely. the type still says `| null`, so narrow.
  const currentOrg = me.org;

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-2 py-1.5 rounded-md hover:bg-muted/40 text-left"
        aria-expanded={open}
      >
        <div className="min-w-0">
          <div className="text-sm font-semibold tracking-tight truncate">
            {currentOrg?.name ?? "sf-voice"}
          </div>
          <div className="text-xs text-muted-foreground truncate">
            {currentOrg ? currentOrg.slug : "debugger"}
          </div>
        </div>
        <span className="ml-2 text-muted-foreground text-xs">▾</span>
      </button>
      {open && (
        <OrgSwitcherMenu
          currentOrgId={currentOrg?.id ?? null}
          onClose={() => setOpen(false)}
          onCreate={() => {
            setOpen(false);
            navigate({ to: "/create-org" });
          }}
        />
      )}
    </div>
  );
}

function OrgSwitcherMenu({
  currentOrgId,
  onClose,
  onCreate,
}: {
  currentOrgId: string | null;
  onClose: () => void;
  onCreate: () => void;
}) {
  const orgs = useMyOrgs();
  const switchOrg = useSwitchOrg();

  return (
    <div
      className="absolute top-full left-0 mt-1 w-64 z-20 rounded-md border border-border bg-background shadow-lg overflow-hidden"
      // pointer leaves the menu OR clicks outside via the trigger's
      // toggle → close. there's no overlay so we don't trap focus.
      onMouseLeave={onClose}
    >
      <div className="px-3 py-2 text-[10px] uppercase tracking-wide text-muted-foreground">
        your orgs
      </div>
      <div className="max-h-64 overflow-y-auto">
        {orgs.isLoading && (
          <div className="px-3 py-2 text-xs text-muted-foreground">
            loading…
          </div>
        )}
        {orgs.data?.map((o) => {
          const active = o.id === currentOrgId;
          return (
            <button
              key={o.id}
              type="button"
              disabled={active || switchOrg.isPending}
              onClick={() => {
                if (active) return;
                switchOrg.mutate(o.id, { onSuccess: onClose });
              }}
              className={cn(
                "w-full text-left px-3 py-2 hover:bg-muted/40",
                active && "bg-muted/60",
              )}
            >
              <div className="text-xs font-medium text-foreground truncate flex items-center gap-2">
                {o.name}
                {active && (
                  <span className="text-[9px] uppercase text-muted-foreground">
                    current
                  </span>
                )}
              </div>
              <div className="text-[10px] text-muted-foreground truncate">
                {o.slug} · {o.role}
              </div>
            </button>
          );
        })}
        {orgs.data && orgs.data.length === 0 && !orgs.isLoading && (
          <div className="px-3 py-2 text-xs text-muted-foreground">
            no orgs yet
          </div>
        )}
      </div>
      <button
        type="button"
        onClick={onCreate}
        className="w-full text-left px-3 py-2 text-xs text-foreground hover:bg-muted/40 border-t border-border"
      >
        + create new org
      </button>
    </div>
  );
}

function AccountMenu({ me }: { me: Me }) {
  const [open, setOpen] = useState(false);
  const logout = useLogout();
  const navigate = useNavigate();

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center gap-2 px-3 py-2 rounded-md hover:bg-muted/40 text-left"
      >
        <div className="w-6 h-6 rounded-full bg-muted flex items-center justify-center text-[10px] font-semibold uppercase text-foreground">
          {me.user.email.slice(0, 2)}
        </div>
        <div className="flex-1 min-w-0">
          <div className="text-xs font-medium text-foreground truncate">
            {me.user.display_name ?? me.user.email}
          </div>
          <div className="text-[10px] text-muted-foreground truncate">
            {me.user.email}
          </div>
        </div>
      </button>
      {open && (
        <div
          className="absolute bottom-full left-0 mb-2 w-full rounded-md border border-border bg-background shadow-lg overflow-hidden"
          onMouseLeave={() => setOpen(false)}
        >
          <button
            type="button"
            onClick={() => {
              setOpen(false);
              navigate({ to: "/user-settings" });
            }}
            className="w-full text-left px-3 py-2 text-xs text-muted-foreground hover:bg-muted/40 hover:text-foreground border-b border-border"
          >
            user settings
          </button>
          <button
            type="button"
            onClick={() => {
              setOpen(false);
              logout.mutate(undefined, {
                onSuccess: () => navigate({ to: "/login" }),
              });
            }}
            className="w-full text-left px-3 py-2 text-xs text-muted-foreground hover:bg-muted/40 hover:text-foreground"
          >
            sign out
          </button>
        </div>
      )}
    </div>
  );
}
