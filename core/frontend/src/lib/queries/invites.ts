import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../api";
import { qk } from "./keys";

export function useMembers() {
   return useQuery({ queryKey: qk.members(), queryFn: api.listMembers });
}

export function useInvites() {
   return useQuery({ queryKey: qk.invites(), queryFn: api.listInvites });
}

export function useCreateInvite() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (body: Parameters<typeof api.createInvite>[0]) =>
         api.createInvite(body),
      onSuccess: () => qc.invalidateQueries({ queryKey: qk.invites() }),
   });
}

export function useRevokeInvite() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (id: string) => api.revokeInvite(id),
      onSuccess: () => qc.invalidateQueries({ queryKey: qk.invites() }),
   });
}

export function useInvitePreview(token: string | undefined) {
   return useQuery({
      queryKey: token ? qk.invitePreview(token) : ["invites", "none"],
      queryFn: () => api.previewInvite(token!),
      enabled: Boolean(token),
   });
}

export function useAcceptInvite() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (token: string) => api.acceptInvite(token),
      onSuccess: () => {
         qc.invalidateQueries({ queryKey: qk.me() });
         qc.invalidateQueries({ queryKey: qk.members() });
      },
   });
}
