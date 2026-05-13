# sf-voice-api production image.
#
# build context is the repo root (the rust workspace lives there).
# Dockerfile.dockerignore next to this file scopes the context to just
# the bits we need.
#
# build: docker build -f core/backend/api/Dockerfile -t sf-voice-api .

FROM rust:1.82-bookworm AS builder

# duckdb is `bundled` in core/backend/api/Cargo.toml — it compiles libduckdb
# from source on every clean build, so we need a real c++ toolchain.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# copy the workspace manifests + the api crate. the dockerignore keeps
# everything else (apps/, cpp/, infra/, .git, target/, …) out of the
# context, so this is faster than it looks.
COPY Cargo.toml Cargo.lock ./
COPY core/backend/api/Cargo.toml core/backend/api/Cargo.toml
COPY core/backend/api/src core/backend/api/src

# release build. duckdb-bundled is the slow step (~5min cold, cached
# in subsequent builds via GH Actions cache-from).
RUN cargo build --release --bin sf-voice-api


FROM debian:bookworm-slim AS runner

# ca-certs for outbound tls (mysql, anything else). libstdc++ + libgcc
# for the duckdb static c++ runtime baked into the binary.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libstdc++6 \
    libgcc-s1 \
  && rm -rf /var/lib/apt/lists/*

# non-root for the runtime user. uid matches what bootstrap-api.sh
# chowns /srv/sf-voice-api/data to.
RUN useradd --system --uid 1001 --user-group --no-create-home apiuser

WORKDIR /app
COPY --from=builder /build/target/release/sf-voice-api /usr/local/bin/sf-voice-api

USER apiuser
EXPOSE 8080

CMD ["sf-voice-api"]
