// pathless layout route for authenticated surfaces — / (calls), /calls/*,
// /settings/*. checks /api/me; redirects to /login if not authenticated.
//
// the actual product shell lives in <Layout />; this wrapper is just the
// auth gate.

import { useEffect } from "react";
import {
  Outlet,
  createRoute,
  useLocation,
  useNavigate,
} from "@tanstack/react-router";
import { Layout } from "@/components/layout/Layout";
import { useMe } from "@/lib/queries";
import { ApiError } from "@/lib/api";
import { rootRoute } from "./root";

function AuthedShell() {
  const { data: me, isLoading, error } = useMe();
  const navigate = useNavigate();
  const location = useLocation();

  // redirect on 401. don't redirect on transient network errors — those
  // surface as the loading / error state inside Layout.
  useEffect(() => {
    if (error instanceof ApiError && error.status === 401) {
      navigate({ to: "/login" });
    }
  }, [error, navigate]);

  // authed but no current org → send to /create-org. skip when already
  // there so the redirect doesn't loop.
  useEffect(() => {
    if (me && !me.org && location.pathname !== "/create-org") {
      navigate({ to: "/create-org" });
    }
  }, [me, location.pathname, navigate]);

  if (isLoading) {
    return (
      <div className="theme-dark min-h-screen bg-background flex items-center justify-center text-muted-foreground text-sm">
        loading…
      </div>
    );
  }

  if (!me) {
    // unauth + not loading → effect above will navigate. avoid flashing
    // the dark shell with no data.
    return <div className="theme-dark min-h-screen bg-background" />;
  }

  // orgless user on /create-org: render the page WITHOUT Layout, since
  // Layout expects a non-null org (sidebar / org switcher / etc).
  if (!me.org) {
    return (
      <div className="theme-dark min-h-screen bg-background">
        <Outlet />
      </div>
    );
  }

  return (
    <Layout me={me}>
      <Outlet />
    </Layout>
  );
}

export const authedLayoutRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: "_authed",
  component: AuthedShell,
});
