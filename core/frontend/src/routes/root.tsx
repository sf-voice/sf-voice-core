// root route — owns the layout shell. every child route renders inside
// <Outlet /> in Layout.

import { createRootRoute } from "@tanstack/react-router";
import { Layout } from "@/components/Layout";

export const rootRoute = createRootRoute({
  component: Layout,
});
