# infra/MEMORY.md

Decisions specific to `infra/` — Docker compose, Caddy, GitHub Actions,
droplet bootstrap, sfctl deploy console.

Read this file before making changes that touch the deploy pipeline or
the droplet's filesystem layout.

---

## [2026-06-02] — mysql bind mount uses absolute legacy path
**What was decided:** `compose.prod.yml`'s mysql service mounts
`/srv/mysql/data:/var/lib/mysql` (absolute path), NOT `./data/mysql:`
relative to `/srv/sf-voice/`. Don't switch this without first
`rsync`-ing data from the legacy path to the new location.

**Why:** Production mysql data has lived in `/srv/mysql/data` since
before the `/srv/sf-voice/` layout migration. The stale container with
`container_name: mysql` was still serving prod from there on 2026-06-01.
Changing the bind mount without copying the data first would have
pointed compose at an empty directory — silent data loss visible only
after the next deploy cycle.

**What was rejected:** Migrating the data to
`/srv/sf-voice/data/mysql/` (the layout the rest of the stack uses).
Requires downtime + rsync + verification cycle — deferred until there's
no production traffic to lose.

## [2026-06-02] — Per-service GH concurrency + droplet-side flock
**What was decided:** `deploy-console.yml` uses
`concurrency: deploy-console-${{ inputs.service }}` so api and
frontend deploys don't queue behind each other. The race on
`/srv/sf-voice/env/images.env` is now guarded by `flock` inside
`sfctl::set_image_tag` (30s timeout exclusive lock on
`env/images.env.lock`).

**Why:** Earlier `deploy-console-droplet` group (one-at-a-time across
all services) caused frontend deploys to be cancelled when api deploys
queued ahead of them — GH Actions only keeps the newest pending run
per concurrency group, even with `cancel-in-progress: false`. Moving
race protection droplet-side (flock) lets different services deploy
concurrently while still preventing tag-write races.

**What was rejected:** Keeping the global concurrency group +
accepting cancellations. Adds operator toil (every deploy that gets
cancelled has to be re-triggered manually).

## [2026-06-02] — Stale containers from legacy /srv layout block recreates
**What was decided:** When `compose up` errors with
`Container <name> Conflict. The container name "/<name>" is already in
use`, the fix is `docker rm -f <name>` on the droplet — the legacy
container's compose-project label doesn't match the new `sf-voice`
project. Data lives in the bind mount, NOT in the container, so the rm
is safe as long as the bind paths match.

**Why:** Hit this 3 times during the 2026-06-01 outage (caddy, api,
mysql). Each legacy service had its own `/srv/<service>/` compose
project; container names are pinned but project labels differ.
`docker compose` refuses to take over a container whose project label
doesn't match.

**What was rejected:** Dropping `container_name:` pins from
`compose.prod.yml` (would let compose auto-generate names like
`sf-voice-api-1`). Caddy's reverse_proxy targets currently use the
pinned short names (`api:8080`, etc) — switching means updating
Caddyfile and operator muscle memory for `docker logs`. Deferred.

## [2026-06-02] — nginx X-App-Sha header (cross-ref)
See `core/frontend/MEMORY.md` for the decision — the convention lives
with the frontend (primary actor: `core/frontend/nginx.conf` +
`core/frontend/Dockerfile`). `verify_frontend_version` in
`sfctl deploy.sh` reads the header for smoke-check verification.

## [2026-06-02] — Env plumbing has four places that must agree
**What was decided:** Adding a new env var the api reads requires
updating all of:
1. `.github/workflows/deploy-console.yml` `env:` block — read secret
2. `.github/workflows/deploy-console.yml` `envs:` CSV — forward to ssh
3. `.github/workflows/deploy-console.yml` `script:` exports — for the
   staging-deploy override block (if applicable)
4. `infra/deploy/sfctl.d/common.sh` `write_env_file` arg list

Forgetting any one results in the api seeing the var as empty + a silent
runtime feature disable. Until Phase 2 of the env refactor lands,
maintaining all four is mandatory.

**Why:** Bit us twice on 2026-06-01: `AUTUMN_SECRET_KEY` was set as a
GH secret but missing from `common.sh` write list, so the api logged
"AUTUMN_SECRET_KEY not set" despite the secret existing. `QDRANT_URL`
was missing from the workflow `env:` block, so the api saw an empty
value and validate-or-exit killed it.

**What was rejected:** Phase 2 manifest refactor (single
`api.env.spec` file + `toJSON(secrets)` ship via scp + sfctl reads
from spec) — designed but not implemented yet. Land this when there's
a non-fire-fighting window. Tracked in
`/Users/lois/.claude/plans/optimized-churning-fairy.md`.

## [2026-06-02] — Rust CI: cargo-chef + mold + GHA cache mode=max
**What was decided:** `core/backend/api/Dockerfile` uses the cargo-chef
multi-stage pattern (`chef` → `planner` → `cook` → `builder`) with mold
linker installed in the chef stage and `RUSTFLAGS="-C
link-arg=-fuse-ld=mold"`. The workflow `build` job uses `cache-to:
type=gha,mode=max,scope=sf-voice-api`. The PR `test` job has no docker
build (cargo proves it compiles; the push-to-main build catches
Dockerfile breakage).

**Why:** Cold builds went from 15+ min to 10–12 min; warm builds went
from 8–15 min to 1–3 min for source-only changes (cargo-chef dep layer
stays cached). The redundant PR docker build added 2–4 min per PR
that's no longer paid.

**What was rejected:** Depot (tried, removed in commit `edf48a0` —
costs extra service to maintain). sccache (more infra to maintain than
the win is worth for now). Per-PR docker build via path-filter
(complexity for a marginal latency win once cargo-chef is hot).

## [2026-06-05] — AgentMail env is API runtime config
**What was decided:** Agent onboarding email delivery uses
`AGENTMAIL_API_KEY`, `AGENTMAIL_INBOX_ID`, and optional
`AGENTMAIL_API_BASE` as runtime env vars for the core API. These
secrets are forwarded exclusively by the `sf-voice/core` repository's
own `deploy-console.yml` and `preview.yml` workflows (via
`core/infra/deploy/sfctl.d/common.sh` `write_service_env` and
`core/infra/deploy/sfctl.d/preview.sh` `preview_write_env`). This
parent repo does not forward them — `preview.yml` was removed,
`preview.sh` was stripped to destroy-only, `deploy-console.yml`
excludes api, and `write_service_env` no longer has an `api)` case.

**Why:** The agent onboarding route can still fall back to
`agentmail_not_configured`, but production should send setup codes
without manual droplet env edits.

**What was rejected:** Adding AgentMail to backend fail-fast env
validation. The route is optional and should degrade cleanly when the
secrets are absent in local or fork-preview contexts.

## [2026-06-05] — Core deployment moves to the core repo
**What was decided:** Core API/frontend deployment ownership is moving
to `sf-voice/core`. The core repo now has standalone Rust/pnpm workspace
files and its own `.github/workflows/{api,frontend,preview,deploy-console}.yml`.
The new core deploy console is intentionally limited to `api` and `frontend`
and forwards only core runtime env.

**Why:** Keeping core deploy workflows and core runtime secrets in the
parent `sf-voice-core` repo exposes more secret surface than needed.
The parent repo should keep shared droplet/app operations; core should
own core image builds and core deploys.

**What was rejected:** Copying the parent deploy console wholesale into
core. That would drag ellie/resto/caddy/mysql/redis operational secrets
into the core repo, which is the problem this split is meant to remove.

## [2026-06-02] — Stateful services don't belong in deploy_all
**What was decided:** **PLANNED, NOT YET FIXED.** `sfctl deploy_all`
currently loops `mysql qdrant redis caddy resto ellie api frontend`,
recreating every container including the stateful ones. This causes
container-name conflicts on every full deploy and risks data loss if
bind paths ever drift. The fix is to remove `mysql qdrant redis` from
`deploy_all` and require an explicit `sfctl restart-data <service>`
command for the rare cases where they need to bounce.

**Why:** Code pushes have no business recreating data containers — the
binary inside is identical and the container restart is pure churn.
Each unnecessary recreate is also another chance for the legacy-label
container-name conflict to bite.

**What was rejected:** Keeping the status quo. Will land when the next
outage forces another container conflict.

## [2026-06-02] — Direct pushes to main bypass PR CI
**What was decided:** **PLANNED, NOT YET FIXED.** Branch protection on
`sf-voice/sf-voice-core` and `sf-voice/core` is not configured. Several
2026-06-01 outages were caused by direct pushes to main that wouldn't
have passed PR review (e.g. the migration that took prod down was a
direct push). Need: require PRs + require status checks (sf-voice-api
test) + require linear history.

**Why:** Direct submodule bumps (`chore: bump core`) include arbitrary
core code changes without code review. The 2026-06-01 migration
incident shipped on a direct push with no CI gate.

**What was rejected:** Status quo. Will land alongside the next infra
cleanup.
