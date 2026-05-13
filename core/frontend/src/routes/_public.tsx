// pathless layout route for unauthenticated surfaces — /login, /signup,
// /accept-invite. wraps every child in <PublicLayout /> which provides
// the light brand theme.

import { createRoute } from "@tanstack/react-router";
import { PublicLayout } from "@/components/PublicLayout";
import { rootRoute } from "./root";

export const publicLayoutRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: "_public",
  component: PublicLayout,
});
