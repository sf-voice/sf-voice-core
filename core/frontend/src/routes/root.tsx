// root route — pathless container. layout-routes below split the tree
// into public (light theme) and authed (dark theme, guarded) branches.

import { Outlet, createRootRoute } from "@tanstack/react-router";

export const rootRoute = createRootRoute({
  component: () => <Outlet />,
});
