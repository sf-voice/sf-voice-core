import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../api";
import { qk } from "./keys";

export function useUpdateProfile() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (body: Parameters<typeof api.updateProfile>[0]) =>
         api.updateProfile(body),
      onSuccess: () => qc.invalidateQueries({ queryKey: qk.me() }),
   });
}

export function useChangePassword() {
   return useMutation({
      mutationFn: (body: Parameters<typeof api.changePassword>[0]) =>
         api.changePassword(body),
   });
}

export function useChangeEmail() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (body: Parameters<typeof api.changeEmail>[0]) =>
         api.changeEmail(body),
      onSuccess: () => qc.invalidateQueries({ queryKey: qk.me() }),
   });
}

export function useSessions() {
   return useQuery({ queryKey: qk.sessions(), queryFn: api.listSessions });
}

export function useRevokeSession() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (id: string) => api.revokeSession(id),
      onSuccess: () => qc.invalidateQueries({ queryKey: qk.sessions() }),
   });
}
