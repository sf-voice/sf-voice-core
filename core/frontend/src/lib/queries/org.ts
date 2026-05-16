import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, type UpdateOrgBody } from "../api";
import { qk } from "./keys";

export function useOrg() {
   return useQuery({ queryKey: qk.org(), queryFn: api.getOrg });
}

export function useUpdateOrg() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (body: UpdateOrgBody) => api.updateOrg(body),
      onSuccess: () => {
         qc.invalidateQueries({ queryKey: qk.org() });
      },
   });
}

export function useMyOrgs() {
   return useQuery({ queryKey: qk.myOrgs(), queryFn: api.listMyOrgs });
}

export function useSwitchOrg() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (org_id: string) => api.switchOrg(org_id),
      onSuccess: (data) => {
         qc.setQueryData(qk.me(), data);
         // org-scoped caches are stale after a switch.
         qc.invalidateQueries({ queryKey: qk.calls() });
         qc.invalidateQueries({ queryKey: qk.org() });
         qc.invalidateQueries({ queryKey: qk.members() });
         qc.invalidateQueries({ queryKey: qk.invites() });
         qc.invalidateQueries({ queryKey: qk.bucket() });
      },
   });
}

// POST /api/orgs — create a brand-new org for the current user.
// returns updated Me with the new org set as current.
export function useCreateOrg() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (name: string) => api.createOrg(name),
      onSuccess: (data) => qc.setQueryData(qk.me(), data),
   });
}

export function useBucket() {
   return useQuery({ queryKey: qk.bucket(), queryFn: api.getBucket });
}
