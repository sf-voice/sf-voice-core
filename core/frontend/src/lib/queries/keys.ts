// react-query cache keys. one place to keep them consistent so cache
// invalidation doesn't drift between callers.

export const qk = {
   me: () => ["me"] as const,
   myOrgs: () => ["me", "orgs"] as const,
   calls: () => ["calls"] as const,
   call: (id: string) => ["calls", id] as const,
   transcripts: (id: string) => ["calls", id, "transcripts"] as const,
   org: () => ["org"] as const,
   slice: (id: string) => ["slices", id] as const,
   members: () => ["org", "members"] as const,
   invites: () => ["org", "invites"] as const,
   invitePreview: (token: string) => ["invites", token] as const,
   sessions: () => ["me", "sessions"] as const,
   bucket: () => ["org", "bucket"] as const,
} as const;
