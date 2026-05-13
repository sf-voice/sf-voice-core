import { QueryClient } from "@tanstack/react-query";

// single client for the whole app. tuned for a debugging tool: data
// staleness matters less than fast nav, so cache aggressively. tweak
// when a real workflow surfaces a need.
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});
