// route tree assembly. layout-route structure:
//   rootRoute (pathless)
//     ├── publicLayoutRoute (PublicLayout, light theme)
//     │     ├── /signup
//     │     └── /login
//     └── authedLayoutRoute (Layout, dark theme + auth gate)
//           ├── /
//           ├── /calls/$callId
//           ├── /calls/$callId/slices/$sliceId
//           ├── /settings/buckets
//           └── /settings/org

import { createRouter } from "@tanstack/react-router";
import { rootRoute } from "./routes/root";
import { publicLayoutRoute } from "./routes/_public";
import { authedLayoutRoute } from "./routes/_authed";
import { loginRoute } from "./routes/login";
import { signupRoute } from "./routes/signup";
import { callsIndexRoute } from "./routes/calls-index";
import { callDetailRoute } from "./routes/call-detail";
import { sliceDetailRoute } from "./routes/slice-detail";
import { settingsBucketsRoute } from "./routes/settings-buckets";
import { settingsOrgRoute } from "./routes/settings-org";

const routeTree = rootRoute.addChildren([
  publicLayoutRoute.addChildren([loginRoute, signupRoute]),
  authedLayoutRoute.addChildren([
    callsIndexRoute,
    callDetailRoute,
    sliceDetailRoute,
    settingsBucketsRoute,
    settingsOrgRoute,
  ]),
]);

export const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
