// route tree assembly. code-based (no file-based plugin in v1) because
// it's simpler to onboard and the tree is small. swap to file-based with
// @tanstack/router-plugin when the tree outgrows this file.

import { createRouter } from "@tanstack/react-router";
import { rootRoute } from "./routes/root";
import { callsIndexRoute } from "./routes/calls-index";
import { callDetailRoute } from "./routes/call-detail";
import { sliceDetailRoute } from "./routes/slice-detail";
import { settingsBucketsRoute } from "./routes/settings-buckets";
import { settingsOrgRoute } from "./routes/settings-org";

const routeTree = rootRoute.addChildren([
  callsIndexRoute,
  callDetailRoute,
  sliceDetailRoute,
  settingsBucketsRoute,
  settingsOrgRoute,
]);

export const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
