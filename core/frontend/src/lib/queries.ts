// react-query hooks. one place to keep cache keys consistent so cache
// invalidation doesn't drift between callers.

import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { api, type UpdateOrgBody } from "./api";

export const qk = {
  calls: () => ["calls"] as const,
  call: (id: string) => ["calls", id] as const,
  transcripts: (id: string) => ["calls", id, "transcripts"] as const,
  org: () => ["org"] as const,
  slice: (id: string) => ["slices", id] as const,
} as const;

export function useCalls() {
  return useQuery({ queryKey: qk.calls(), queryFn: api.listCalls });
}

export function useCall(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.call(id) : ["calls", "none"],
    queryFn: () => api.getCall(id!),
    enabled: Boolean(id),
  });
}

export function useTranscripts(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.transcripts(id) : ["calls", "none", "transcripts"],
    queryFn: () => api.listTranscripts(id!),
    enabled: Boolean(id),
  });
}

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

export function useSlice(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.slice(id) : ["slices", "none"],
    queryFn: () => api.getSlice(id!),
    enabled: Boolean(id),
  });
}
