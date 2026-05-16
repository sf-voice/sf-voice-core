import { request } from "./client";
import type {
   ChangeEmailBody,
   ChangePasswordBody,
   SessionDto,
   UpdateProfileBody,
   User,
} from "./types";

export const profileApi = {
   updateProfile: (body: UpdateProfileBody) =>
      request<User>("/api/me/profile", { method: "PATCH", json: body }),
   changePassword: (body: ChangePasswordBody) =>
      request<null>("/api/me/password", { method: "POST", json: body }),
   changeEmail: (body: ChangeEmailBody) =>
      request<User>("/api/me/email", { method: "POST", json: body }),
   listSessions: () => request<SessionDto[]>("/api/me/sessions"),
   revokeSession: (id: string) =>
      request<null>(`/api/me/sessions/${id}`, { method: "DELETE" }),
};
