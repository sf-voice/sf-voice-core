# sf-voice frontend production image.
# rspack build → static files → nginx-alpine on :3000.
#
# build context is the repo root (pnpm workspace lives there).
# Dockerfile.dockerignore next to this file scopes context to just the
# bits we need.
#
# build: docker build -f core/frontend/Dockerfile -t sf-voice-frontend .

FROM node:22-alpine AS builder

# pnpm via corepack — keeps the version pinned to whatever's declared in
# the workspace, no separate `npm i -g pnpm` step needed.
RUN corepack enable

WORKDIR /build

# copy manifests first so the install layer caches when only source
# files change.
COPY pnpm-workspace.yaml pnpm-lock.yaml package.json* ./
COPY core/frontend/package.json core/frontend/package.json

# --frozen-lockfile fails if the lock would drift — what we want in ci.
# --filter limits install to the frontend workspace + its deps; we don't
# need every package's deps for this image.
RUN pnpm install --frozen-lockfile --filter @sf-voice/frontend...

# now bring in the source and build.
COPY core/frontend core/frontend
RUN pnpm --filter @sf-voice/frontend build


FROM nginx:1.27-alpine AS runner

# replace the default site config with one that:
#   - listens on 3000 (matches infra/deploy/Caddyfile → frontend:3000)
#   - serves the spa with try_files fallback to index.html
#   - sets aggressive cache headers on hashed assets
COPY core/frontend/nginx.conf /etc/nginx/conf.d/default.conf

# rspack outputs to ./dist per core/frontend/rspack.config.ts.
COPY --from=builder /build/core/frontend/dist /usr/share/nginx/html

EXPOSE 3000

# nginx-alpine default CMD is correct; keeping the inherited one.
