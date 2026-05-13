// react-query hooks. one place to keep cache keys consistent so cache
// invalidation doesn't drift between callers.

import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  api,
  ApiError,
  type LoginBody,
  type SignupBody,
  type UpdateOrgBody,
} from "./api";

export const qk = {
  me: () => ["me"] as const,
  calls: () => ["calls"] as const,
  call: (id: string) => ["calls", id] as const,
  transcripts: (id: string) => ["calls", id, "transcripts"] as const,
  org: () => ["org"] as const,
  slice: (id: string) => ["slices", id] as const,
} as const;

// auth ──────────────────────────────────────────────────────────────────

export function useMe() {
  return useQuery({
    queryKey: qk.me(),
    queryFn: api.me,
    // 401 means logged out — short-circuit to null instead of error so
    // route guards can branch on `me === null`.
    retry: (failureCount, err) => {
      if (err instanceof ApiError && err.status === 401) return false;
      return failureCount < 1;
    },
  });
}

export function useSignup() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: SignupBody) => api.signup(body),
    onSuccess: (data) => qc.setQueryData(qk.me(), data),
  });
}

export function useLogin() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: LoginBody) => api.login(body),
    onSuccess: (data) => qc.setQueryData(qk.me(), data),
  });
}

export function useLogout() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.logout(),
    onSuccess: () => {
      qc.setQueryData(qk.me(), null);
      qc.clear(); // drop all cached data on logout
    },
  });
}

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

export function useCreateSlice(callId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: {
      start_ms: number;
      end_ms: number;
      prompt_text: string;
    }) => api.createSlice(callId, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: qk.call(callId) });
    },
  });
}

export function useCreateTranscribeRun(callId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.createTranscribeRun(callId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: qk.transcripts(callId) });
    },
  });
}
