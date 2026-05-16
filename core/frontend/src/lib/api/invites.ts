import { request } from "./client";
import type {
   AcceptInviteResponse,
   InviteDto,
   InvitePreview,
   MemberDto,
} from "./types";

export const invitesApi = {
   listMembers: () => request<MemberDto[]>("/api/org/members"),
   listInvites: () => request<InviteDto[]>("/api/org/invites"),
   createInvite: (body: { email: string; role?: "owner" | "member" }) =>
      request<InviteDto>("/api/org/invites", { method: "POST", json: body }),
   revokeInvite: (id: string) =>
      request<null>(`/api/org/invites/${id}`, { method: "DELETE" }),
   previewInvite: (token: string) =>
      request<InvitePreview>(`/api/invites/${token}`),
   acceptInvite: (token: string) =>
      request<AcceptInviteResponse>(`/api/invites/${token}/accept`, {
         method: "POST",
      }),
};
