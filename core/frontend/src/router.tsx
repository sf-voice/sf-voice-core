// route tree assembly. layout-route structure:
//   rootRoute (pathless)
//     ├── publicLayoutRoute (PublicLayout, light theme)
//     │     ├── /signup
//     │     ├── /login
//     │     └── /accept-invite/$token
//     └── authedLayoutRoute (Layout, dark theme + auth gate)
//           ├── /
//           ├── /calls/$callId
//           ├── /calls/$callId/slices/$sliceId
//           ├── /settings/buckets
//           ├── /settings/org
//           ├── /settings/team
//           ├── /settings/billing
//           ├── /user-settings
//           ├── /create-org           (no Layout — orgless fallback)
//           ├── /admin
//           └── /admin/_internal/youtube

import { createRouter } from "@tanstack/react-router";
import { rootRoute } from "./routes/root";
import { publicLayoutRoute } from "./routes/_public";
import { authedLayoutRoute } from "./routes/_authed";
import { loginRoute } from "./routes/login";
import { signupRoute } from "./routes/signup";
import { acceptInviteRoute } from "./routes/accept-invite";
import { callsIndexRoute } from "./routes/calls/calls-index";
import { callDetailRoute } from "./routes/calls/call-detail";
import { sliceDetailRoute } from "./routes/calls/slice-detail";
import { settingsBucketsRoute } from "./routes/settings-buckets";
import { settingsOrgRoute } from "./routes/settings-org";
import { settingsTeamRoute } from "./routes/settings-team";
import { settingsBillingRoute } from "./routes/settings-billing";
import { userSettingsRoute } from "./routes/user-settings";
import { createOrgRoute } from "./routes/create-org";
import { adminRoute } from "./routes/admin/admin";
import { internalYoutubeRoute } from "./routes/admin/youtube";

const routeTree = rootRoute.addChildren([
  publicLayoutRoute.addChildren([loginRoute, signupRoute, acceptInviteRoute]),
  authedLayoutRoute.addChildren([
    callsIndexRoute,
    callDetailRoute,
    sliceDetailRoute,
    settingsBucketsRoute,
    settingsOrgRoute,
    settingsTeamRoute,
    settingsBillingRoute,
    userSettingsRoute,
    createOrgRoute,
    adminRoute,
    internalYoutubeRoute,
  ]),
]);

export const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
