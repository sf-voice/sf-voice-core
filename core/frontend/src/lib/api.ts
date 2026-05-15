const API_BASE_URL = "http://localhost:8080";

export class ApiError extends Error {
   constructor(
      public status: number,
      public statusText: string,
      public path: string,
      message: string,
   ) {
      super(message);
   }
}

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
      // include cookies on every request so the session cookie travels
      // from localhost:3000 → :8080 (and prod cross-origin if that ever
      // happens). backend CORS allows credentials for these origins.
      credentials: "include",
      headers,
      body: init?.json !== undefined ? JSON.stringify(init.json) : init?.body,
   });
   if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new ApiError(res.status, res.statusText, path, text || res.statusText);
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

// ── auth ─────────────────────────────────────────────────────────────────

export type User = {
   id: string;
   email: string;
   display_name: string | null;
   created_at: string;
};

export type Me = {
   user: User;
   org: { id: string; name: string; slug: string };
};

export type SignupBody = {
   email: string;
   password: string;
   org_name?: string;
};

export type LoginBody = {
   email: string;
   password: string;
};

// ── user-settings types ──────────────────────────────────────────────────

export type SessionDto = {
   id: string;
   ip: string | null;
   user_agent: string | null;
   created_at: string;
   last_used_at: string | null;
   is_current: boolean;
};

export type UpdateProfileBody = {
   display_name: string | null;
};

export type ChangePasswordBody = {
   current_password: string;
   new_password: string;
};

export type ChangeEmailBody = {
   new_email: string;
   current_password: string;
};

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

   // auth
   signup: (body: SignupBody) =>
      request<Me>("/api/auth/signup", { method: "POST", json: body }),
   login: (body: LoginBody) =>
      request<Me>("/api/auth/login", { method: "POST", json: body }),
   logout: () => request<null>("/api/auth/logout", { method: "POST" }),
   me: () => request<Me>("/api/me"),

   // per-user settings
   updateProfile: (body: UpdateProfileBody) =>
      request<User>("/api/me/profile", { method: "PATCH", json: body }),
   changePassword: (body: ChangePasswordBody) =>
      request<null>("/api/me/password", { method: "POST", json: body }),
   changeEmail: (body: ChangeEmailBody) =>
      request<User>("/api/me/email", { method: "POST", json: body }),
   listSessions: () => request<SessionDto[]>("/api/me/sessions"),
   revokeSession: (id: string) =>
      request<null>(`/api/me/sessions/${id}`, { method: "DELETE" }),

   // multi-org + invites (phase I)
   listMyOrgs: () => request<OrgMembershipDto[]>("/api/me/orgs"),
   switchOrg: (org_id: string) =>
      request<Me>("/api/me/switch-org", {
         method: "POST",
         json: { org_id },
      }),
   createOrg: (name: string) =>
      request<Me>("/api/orgs", { method: "POST", json: { name } }),
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

   // bucket connection (phase J)
   getBucket: () => request<BucketStatus>("/api/org/bucket"),
   getBucketSetup: (q: {
      bucket_name?: string;
      bucket_prefix?: string;
      bucket_region?: string;
      aws_account_id?: string;
   }) => {
      const params = new URLSearchParams();
      if (q.bucket_name) params.set("bucket_name", q.bucket_name);
      if (q.bucket_prefix) params.set("bucket_prefix", q.bucket_prefix);
      if (q.bucket_region) params.set("bucket_region", q.bucket_region);
      if (q.aws_account_id) params.set("aws_account_id", q.aws_account_id);
      const qs = params.toString();
      return request<BucketSetup>(
         `/api/org/bucket/setup${qs ? "?" + qs : ""}`,
      );
   },
   saveBucketRole: (body: SaveBucketRoleBody) =>
      request<BucketStatus>("/api/org/bucket/role", {
         method: "POST",
         json: body,
      }),
   probeBucketRole: (body: ProbeRoleBody) =>
      request<ProbeRoleResponse>("/api/org/bucket/role/probe", {
         method: "POST",
         json: body,
      }),
   saveBucketKeys: (body: SaveBucketKeysBody) =>
      request<BucketStatus>("/api/org/bucket/keys", {
         method: "POST",
         json: body,
      }),
   disconnectBucket: () =>
      request<BucketStatus>("/api/org/bucket", { method: "DELETE" }),
   ingestNow: () =>
      request<{ job_id: string }>("/api/org/bucket/ingest", {
         method: "POST",
      }),
};

// ── multi-org + invites (phase I) types ─────────────────────────────────

export type OrgMembershipDto = {
   id: string;
   name: string;
   slug: string;
   role: "owner" | "member";
   is_current: boolean;
};

export type MemberDto = {
   user_id: string;
   email: string;
   display_name: string | null;
   role: "owner" | "member";
   joined_at: string;
};

export type InviteDto = {
   id: string;
   email: string;
   role: "owner" | "member";
   token: string;
   accept_url: string;
   created_at: string;
   expires_at: string;
   accepted_at: string | null;
};

export type InvitePreview = {
   org_name: string;
   org_slug: string;
   email: string;
   role: "owner" | "member";
   expires_at: string;
   already_accepted: boolean;
   expired: boolean;
};

export type AcceptInviteResponse = {
   org_id: string;
   org_name: string;
   org_slug: string;
};

// ── bucket (phase J) types ──────────────────────────────────────────────

export type BucketStatus = {
   method: "role" | "keys" | null;
   bucket_name: string | null;
   bucket_prefix: string | null;
   bucket_region: string | null;
   bucket_account_id: string | null;
   bucket_role_arn: string | null;
   bucket_access_key_id: string | null;
   bucket_external_id: string | null;
   verified_at: string | null;
};

export type BucketSetup = {
   external_id: string;
   aws_principal: string;
   template_url: string;
   quick_create_url: string;
};

export type SaveBucketRoleBody = {
   bucket_name: string;
   bucket_prefix?: string;
   bucket_region: string;
   role_arn: string;
};

export type SaveBucketKeysBody = {
   bucket_name: string;
   bucket_prefix?: string;
   bucket_region: string;
   access_key_id: string;
   secret_access_key: string;
};

export type ProbeRoleBody = {
   aws_account_id: string;
   bucket_name: string;
   bucket_prefix?: string;
   bucket_region: string;
};

// tagged union from the rust side. `verified` = stop polling, persisted.
// `pending` = role not there yet, keep polling. `failed` = stop polling,
// show error.
export type ProbeRoleResponse =
   | { status: "verified"; role_arn: string; bucket: BucketStatus }
   | { status: "pending"; role_arn: string; reason: string }
   | { status: "failed"; role_arn: string; reason: string };
