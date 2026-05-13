const API_BASE_URL = "http://localhost:8080";

async function request<T>(
   path: string,
   init?: RequestInit & { json?: unknown },
): Promise<T> {
   const headers = new Headers(init?.headers);
   if (init?.json !== undefined) {
      headers.set("content-type", "application/json");
   }
   const res = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      headers,
      body: init?.json !== undefined ? JSON.stringify(init.json) : init?.body,
   });
   if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`api ${path} → ${res.status} ${res.statusText} ${text}`);
   }
   // 204 / empty body → null
   if (res.status === 204) return null as T;
   return (await res.json()) as T;
}

export type Hello = {
   message: string;
   service: string;
   version: string;
};

export type Org = {
   id: string;
   name: string;
   slug: string;
   bucket_name: string | null;
   bucket_prefix: string | null;
   bucket_region: string | null;
   bucket_role_arn: string | null;
   bucket_external_id: string | null;
   config_repo_url: string | null;
   slack_webhook_url: string | null;
   created_at: string;
   updated_at: string;
};

export type Call = {
   id: string;
   org_id: string;
   external_id: string | null;
   started_at: string;
   ended_at: string | null;
   duration_ms: number | null;
   caller_number: string | null;
   destination_number: string | null;
   termination_reason: string | null;
   audio_uri: string | null;
   caller_audio_uri: string | null;
   ai_audio_uri: string | null;
   created_at: string;
   updated_at: string;
};

export type Transcript = {
   id: number;
   call_id: string;
   run_id: string;
   speaker_label: "ai" | "caller" | "unknown";
   start_ms: number;
   end_ms: number;
   text: string;
   confidence: number | null;
   model_version: string;
   created_at: string;
};

export type PromptSlice = {
   id: string;
   call_id: string;
   org_id: string;
   start_ms: number;
   end_ms: number;
   prompt_text: string;
   status: "draft" | "sandboxed" | "pr_open" | "merged" | "rejected";
   job_id: string | null;
   pr_url: string | null;
   created_at: string;
   updated_at: string;
};

export type UpdateOrgBody = Partial<
   Pick<
      Org,
      | "config_repo_url"
      | "slack_webhook_url"
      | "bucket_name"
      | "bucket_prefix"
      | "bucket_region"
   >
>;

export const api = {
   hello: () => request<Hello>("/api/hello"),

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

   // GET /api/org + PATCH /api/org — org settings
   getOrg: () => request<Org | null>("/api/org"),
   updateOrg: (body: UpdateOrgBody) =>
      request<Org | null>("/api/org", { method: "PATCH", json: body }),
};
