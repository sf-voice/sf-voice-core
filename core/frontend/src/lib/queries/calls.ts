import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../api";
import { qk } from "./keys";

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
