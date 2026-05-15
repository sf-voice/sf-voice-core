# core/ — deferred work (post-demo)

Work the v1 demo deliberately punts on. Each item has enough context to start cold.

---

## Auth — org signup + login + session

**Status:** deferred. v1 demo uses a fixed org loaded via SQL seed; auth context resolves the demo org from env (`SF_VOICE_DEV_ORG_ID`) on every request.

**Why deferred:** demo focuses on the timeline + eval-harness UX. Auth doesn't change either, just gates access to them.

**What needs to happen later:**
- Backend
  - `users` table: id, email (unique), password_hash (argon2id), created_at
  - `org_users` join table: id, org_id, user_id, role (`owner`/`member`)
  - `sessions` table: id, user_id, expires_at, last_used_at, ip, user_agent
  - Routes: `POST /api/auth/signup` (creates user + org + org_users), `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/me`
  - Session cookie: http-only, secure, sameSite=Lax, signed with `SF_VOICE_SESSION_KEY`
  - Middleware: `auth_required` extracts `org_id` from session, attaches to request extensions, every route reads from there instead of env
- Frontend
  - `/login` and `/signup` routes (unauthenticated)
  - Wrap protected routes with a redirect-to-login guard
  - `useMe()` hook; show email + signout in `Layout.tsx`
- Migration: existing rows have `org_id` set via seed; on first real signup we create a new `orgs` row

**Recommended approach:**
- Email + password (argon2id) for v1.5. OAuth providers can land later.
- Session table over JWT — easier revocation, simpler debugging, fine at our scale.

**Open question:** SSO requirement for enterprise customers? If yes, add OIDC support before public launch.

---

## Customer S3 bucket credentials

**Status:** deferred. v1 demo reads from one sf-voice-owned bucket whose creds are in env (`SF_VOICE_DEMO_AWS_*`).

**Why deferred:** real customer-bucket auth needs secure credential storage which is its own design problem.

**What needs to happen later:**
- Pick a credential model:
  - **(A) IAM role assumption** (recommended). Customer creates an AWS IAM role with sf-voice in the trust policy + an external ID we generate per org. We store role ARN + external ID only. STS AssumeRole on every read. No long-lived secrets in our DB.
  - **(B) Stored keys, encrypted.** Customer pastes access key id + secret in `/settings/buckets`. Encrypt with `age` keyed off `SF_VOICE_SECRETS_KEY` from env. Faster onboarding, real liability if the DB leaks.
- Schema additions in `orgs` are already reserved: `bucket_role_arn`, `bucket_external_id`, plus a future `bucket_access_key_id_encrypted` + `bucket_secret_access_key_encrypted` if going (B).
- Backend `src/s3.rs` becomes per-org-aware: factory that returns an `aws_sdk_s3::Client` configured with the org's credential provider.
- Onboarding doc generator: `/settings/buckets` shows the customer the exact AWS console steps + the JSON trust policy to paste.
- Update `core/backend/AGENT.md` § 1, § 8, § 11 when this lands.

---

## ClickHouse Cloud — per-event telemetry

**Status:** future, documented in `core/backend/AGENT.md` § 6.

**Why deferred:** v1 timeline reads placeholder data synthesized from `transcripts`. Real LLM TTFT spans, VAD probability samples, tool-call traces, and error events live in ClickHouse once the voice runtime starts emitting them.

**What needs to happen later:**
- ClickHouse Cloud account, connection string in env (`CLICKHOUSE_URL`)
- `call_events` MergeTree table per the design in AGENT.md
- Producer side: voice runtime emits events to a Kafka/SQS/HTTP sink; consumer writes batches
- Read API on backend: `GET /api/calls/:id/events?type=...`
- Frontend VadTrack/EventTrack/LatencyOverlay switch from synthesized to real data

---

## Real sandbox spin-up + real GitHub PR creation

**Status:** stubbed. The `sandbox` job emits the canonical 7 steps and writes a placeholder URL.

**What needs to happen later:**
- Sandbox runtime: spin up a customer-config-repo branch, run the customer's voice agent in an isolated container, regenerate the slice's AI response with the modified system prompt
- GitHub App on the per-customer config repo (`orgs.config_repo_url`): commit the new prompt, open a PR, write the PR URL back to `prompt_slices.pr_url`
- A/B audio: store the regenerated TTS at a known location, frontend's `ABPlayer` loads it

---

## Per-org configurable thresholds

**Status:** hardcoded in `core/frontend/src/lib/timeline.ts` (INTERRUPT_OVERLAP_MS, SLOW_TURN_MS, DEAD_AIR_MS).

**Why deferred:** different customers will want different defaults. Out of demo scope.

**What needs to happen later:**
- New `org_thresholds` table or JSON column on `orgs`
- Settings page `/settings/thresholds`
- Frontend reads from `org` query; backwards-compatible fallback to current constants

---

## Live-watch + anomaly auto-detection + cross-call dashboards

**Status:** documented in both AGENT.md files as v2 scope. No code yet.

---

## User settings — backend wiring for per-user account management

**Status:** frontend page lives at `/user-settings` with Profile / Security / Sessions / 2FA / API tokens tabs. Backend endpoints are NOT yet wired.

**What needs to happen later (backend):**
- `PATCH /api/me/profile` — update `users.display_name` and `users.avatar_url`
- `POST /api/me/password` — require `current_password`, hash new with argon2id, **delete every other row in `sessions` for this user** (keep the current one)
- `POST /api/me/email` — require `current_password`, write new email, invalidate other sessions, mark `email_verified_at = NULL` for the new address
- `GET /api/me/sessions` — list `sessions` rows for the current user, flag the one matching the request's cookie as `is_current`
- `DELETE /api/me/sessions/:id` — revoke a single session (refuse if it's the current one — sign-out is a different action)
- Migration: add `users.avatar_url VARCHAR(1024) NULL`, `users.email_verified_at TIMESTAMP NULL`

**Why deferred:** frontend mocks need a real backend to talk to, but the UI / cache invalidation / hooks are all in place. One sitting of backend work unlocks the whole page.

---

## Avatar upload (user-uploaded profile picture)

**Status:** UI in `/user-settings` Profile tab shows a Gravatar derived from the user's email hash. No upload field yet.

**Where artifacts land:** `documents` table (TBD — schema doesn't exist yet). Plan is to use it as a generic per-user / per-org "uploaded file" pointer with org_id, user_id, kind, s3_uri, byte_size, content_type. Avatars are one consumer.

**What needs to happen later:**
- Migration: `CREATE TABLE documents (...)` per above
- `POST /api/me/avatar` — accepts multipart, writes to `s3://sf-voice-assets/avatars/<user_id>/<sha256>.<ext>`, inserts `documents` row, updates `users.avatar_url`
- Image processing: resize to 96×96 on upload (use `image` crate), strip exif
- Frontend: file picker + crop UI in Profile tab. Gravatar stays as the fallback when `avatar_url` is NULL.

---

## Two-factor authentication

**Status:** stub tab in `/user-settings`. No backend.

**What needs to happen later:**
- Migration: `users.totp_secret_encrypted VARBINARY(128) NULL`, `users.totp_verified_at TIMESTAMP NULL`, `user_recovery_codes` table
- Setup flow: `POST /api/me/2fa/begin` returns a freshly-generated TOTP secret + QR string; `POST /api/me/2fa/verify` accepts a code and marks `totp_verified_at`
- Login flow: when `totp_verified_at IS NOT NULL`, login returns `mfa_required` and waits for a follow-up `POST /api/auth/login/mfa` with the code
- Recovery codes: 10 single-use codes, hashed at rest, printed once at setup

---

## API tokens (personal access tokens)

**Status:** stub tab in `/user-settings`. No backend.

**What needs to happen later:**
- Migration: `api_tokens` table: id, user_id, name, token_hash, scopes JSON, last_used_at, created_at, revoked_at
- Tokens are issued as `sfv_<32-byte-base64>`; store sha-256 hash. Show full token to user once at creation only.
- New auth path: `Authorization: Bearer <token>` resolves to the user; org is the user's current_org_id (or per-token org_id if we add scoping).
- Frontend: list, create with name + scopes, copy-to-clipboard one-time view, revoke.

---

## Admin tools — staff console (sf-voice.sh email suffix)

**Status:** `/admin` page lists tools as tiles. Only "YouTube ingest" link is live. Everything else is a stub.

**Gating rule:** see `MEMORY.md` → "sf-voice admin = @sf-voice.sh email". Server enforces via `AdminContext` extractor on every `/api/admin/*` route.

**What needs to happen later (backend):**
- `AdminContext` extractor: pulls `AuthContext`, asserts email suffix, else 403
- `GET /api/admin/orgs` — every org with member count + bucket-connected flag + last_ingest_at + last_call_at
- `GET /api/admin/jobs?status=&kind=&org_id=` — recent jobs across all orgs; support cancel / retry mutations
- `GET /api/admin/users` — every user with their orgs + last_login_at + active session count
- **Spoofing middleware**: when a request has `?spoof=<email>` AND the requester is staff, swap `AuthContext.user_id` + `current_org_id` to the spoofed user's. Log every spoof event with `actor_user_id` + `spoofed_user_id` + path. Reject `?spoof=` from non-staff.

**Frontend:** `/admin/orgs`, `/admin/jobs`, `/admin/users` routes don't exist yet — the tiles link to URLs that 404. Add pages alongside the backend endpoints.

---

## Logs page — design opens

**Status:** specced in `frontend/AGENT.md` § 15. Wireframes needed before implementation.

**Why deferred:** two interaction questions can only be answered with a sketch, not a doc.

**Open questions:**

- **Zoom interaction model.** Spec says `mouse wheel + ⌥` (or `+ / -` keys) toggles zoom. On a page that already scrolls vertically (log list), wheel-zoom fights scroll. Options:
  - (a) Wheel zooms only when the cursor is over the audio-tracks region; plain wheel scrolls the log list anywhere else.
  - (b) Modifier-only — `⌥ + wheel` always zooms, plain wheel always scrolls.
  - (c) Discrete zoom buttons in the filter bar, no wheel zoom at all.
  Pick after a paper sketch of the single-call view and the 24h view side by side.

- **k8s node track shape.** The node filter is customer-facing per `frontend/AGENT.md` § 15, but the *visual* design of the node track depends on infra topology. One shared pod pool → a per-call node band is interesting (shows which pod served which slice). Per-customer dedicated pods → less interesting, maybe a chip on each call row instead. Confirm topology with backend before drawing the track.

**What needs to happen later:**

- Wireframe single-call (zoomed in) and 24h (zoomed out) views side by side.
- Confirm pod topology with backend (`core/backend/AGENT.md` doesn't pin this down yet).
- Pick zoom model, update `frontend/AGENT.md` § 15, then build.

---

## Frontend token migration — `surface-1` / `surface-2`

**Status:** new tokens specced in `frontend/AGENT.md` § 16; not yet defined in `src/index.css`. Most cards and modals currently use `bg-background`.

**Why deferred:** the spec says "migrate opportunistically when touching a file" — but the absence of layered surfaces is what caused the flat-modal bug we hit today (the Connect AWS overlay disappearing into the timeline because card and canvas shared the same color).

**What needs to happen later:**

- Define `--color-surface-1` and `--color-surface-2` in `src/index.css` under `@theme`.
- One-shot pass to migrate the obvious offenders: modal bodies, right-rail panels, popover bodies, active sidebar tile, integration cards, log row hover.
- Leave non-elevated surfaces (page background, empty-state background) on `bg-background`.
- Audit rule: any element rendered *above* another element on the same page is probably wrong if both use `bg-background`.

**Open question:** ship as one dedicated PR, or fold into the first Logs/Settings PR that needs the new surfaces? My vote: one dedicated PR, small, easy to review.
