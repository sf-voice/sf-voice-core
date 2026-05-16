// barrel: assembles the `api` object from per-domain modules and
// re-exports every dto type. call-sites stay on `@/lib/api`.

import { request } from "./client";
import { authApi } from "./auth";
import { callsApi } from "./calls";
import { orgApi } from "./org";
import { profileApi } from "./profile";
import { invitesApi } from "./invites";
import type { Hello } from "./types";

export { ApiError } from "./client";
export type * from "./types";

export const api = {
   hello: () => request<Hello>("/api/hello"),
   ...authApi,
   ...callsApi,
   ...orgApi,
   ...profileApi,
   ...invitesApi,
};
