import { request } from "./client";
import type { Call, PromptSlice, Transcript } from "./types";

export const callsApi = {
   // GET /api/calls — list calls for the resolved org
   listCalls: () => request<Call[]>("/api/calls"),

   // GET /api/calls/:id — single call detail
   getCall: (id: string) => request<Call | null>(`/api/calls/${id}`),

   // GET /api/calls/:id/transcripts — utterance rows for the active run
   listTranscripts: (id: string) =>
      request<Transcript[]>(`/api/calls/${id}/transcripts`),

   // POST /api/calls/:id/slices — create a prompt slice + enqueue sandbox
   createSlice: (
      id: string,
      body: { start_ms: number; end_ms: number; prompt_text: string },
   ) =>
      request<{ slice_id: string; job_id: string }>(`/api/calls/${id}/slices`, {
         method: "POST",
         json: body,
      }),

   // POST /api/calls/:id/transcribe-runs — kick a re-transcribe
   createTranscribeRun: (id: string) =>
      request<{ job_id: string }>(`/api/calls/${id}/transcribe-runs`, {
         method: "POST",
      }),

   // GET /api/slices/:id
   getSlice: (id: string) => request<PromptSlice | null>(`/api/slices/${id}`),
};
