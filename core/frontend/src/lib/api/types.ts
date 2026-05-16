// all dto shapes shared with the rust backend. one file so call-sites
// can do `import type { Call, Org, ... } from "@/lib/api"` via the barrel.

export type Hello = {
   message: string;
   service: string;
   version: string;
};

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

// ── calls + slices + transcripts ─────────────────────────────────────────

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

// ── org ──────────────────────────────────────────────────────────────────

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

// ── per-user settings ────────────────────────────────────────────────────

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

// ── multi-org + invites (phase I) ────────────────────────────────────────

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

// ── bucket (phase J) ─────────────────────────────────────────────────────

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
