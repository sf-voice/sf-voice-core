// shared hook for tab-style URL state.
//
// every tabbed page (User settings, Settings → Buckets, future settings
// pages, etc) reads its active tab from `?tab=<id>` so that:
//   1. refresh preserves the tab
//   2. links to a specific tab are shareable
//   3. browser back/forward navigates between tabs
//
// usage:
//   const tabs = ["profile", "security", "sessions"] as const;
//   const { tab, setTab } = useTabSearch(routeId, tabs, "profile");
//
// generics keep `tab` typed to the literal union; an unknown ?tab=...
// in the URL is silently coerced to the default so we never render a
// non-existent panel.

import { useNavigate, useSearch } from "@tanstack/react-router";

type Search = { tab?: string };

export function useTabSearch<T extends string>(
  routeId: string,
  validTabs: readonly T[],
  defaultTab: T,
): { tab: T; setTab: (t: T) => void } {
  // tanstack's `from` is a string-literal-typed registry id; we cast
  // once on entry so the hook stays usable from any route without
  // dragging a generic route-id type-parameter through every call site.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const search = useSearch({ from: routeId as any }) as Search;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const navigate = useNavigate({ from: routeId as any });

  const tab: T = (validTabs as readonly string[]).includes(search.tab ?? "")
    ? (search.tab as T)
    : defaultTab;

  const setTab = (t: T) => {
    // omit ?tab= entirely when we land on the default; keeps the URL
    // clean ("looks like the original page") for the most common case.
    const nextTab = t === defaultTab ? undefined : t;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    navigate({
      search: (prev: Record<string, unknown>) => ({ ...prev, tab: nextTab }),
      replace: true,
    } as any);
  };

  return { tab, setTab };
}
