// shell for authenticated product surfaces. dark theme wrapper; the
// auth gate lives in routes/_authed.tsx. shows side nav + account menu.

import { Link } from "@tanstack/react-router";
import { type ReactNode, useState } from "react";
import { cn } from "@/lib/utils";
import { useLogout } from "@/lib/queries";
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
        <div>
          <div className="text-sm font-semibold tracking-tight">sf-voice</div>
          <div className="text-xs text-muted-foreground">debugger</div>
        </div>
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
            {me.org.name}
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
