// shell: top bar + left nav + outlet. dark-by-default per AGENT.md.
// nav items use tanstack router's <Link> so active state is automatic.

import { Link, Outlet } from "@tanstack/react-router";
import { cn } from "@/lib/utils";

const navItems = [
  { to: "/", label: "Calls" },
  { to: "/settings/buckets", label: "Buckets" },
  { to: "/settings/org", label: "Org" },
] as const;

export function Layout() {
  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100 flex">
      <aside className="w-56 shrink-0 border-r border-neutral-900 px-4 py-6 flex flex-col gap-6">
        <div>
          <div className="text-sm font-semibold tracking-tight">sf-voice</div>
          <div className="text-xs text-neutral-500">debugger</div>
        </div>
        <nav className="flex flex-col gap-1 text-sm">
          {navItems.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              // index '/' otherwise matches every child route; everything
              // else is fine as a prefix match for child-aware highlight.
              activeOptions={{ exact: item.to === "/" }}
              className={cn(
                "px-3 py-1.5 rounded-md text-neutral-400 hover:text-neutral-100 hover:bg-neutral-900",
              )}
              activeProps={{
                className: "bg-neutral-900 text-neutral-100",
              }}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </aside>
      <main className="flex-1 min-w-0">
        <Outlet />
      </main>
    </div>
  );
}
