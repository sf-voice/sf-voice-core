# Repository layout

This repo is a monorepo housing two related products:

- **The Seasons booking system** — Example application. Single-tenant restaurant booking app. Elixir/Phoenix. Lives under `apps/resto_booking_app` (the integration service) and `apps/ellie_ai` (a zero-framework voice AI app).
- **Core** — Core platform. Rust API (Control Plane) + C++ DBMS (Data Plane) + React frontend. Lives under `core/`.


```
apps/
  resto_booking_app/   ─ Phoenix booking app for The Seasons
  ellie_ai/            ─ voice AI orchestration for the booking app written in elixir
core/
  backend/api/         ─ Rust + Axum API 
  frontend/            ─ React + rspack + Tailwind frontend
  plane/               ─ C++ for data plane management on customer's infra
  inference/           ─ Python for hosted inference 
infra/
  dev/                 ─ docker-compose for local MySQL
  deploy/              ─ prod compose files, Caddyfile, bootstrap scripts
ts/, python/, go/,
rust/, cpp/, java/,
kotlin/, elixir/       ─ language SDKs for the sf-voice media API
docs/                  ─ misc operational notes (telnyx setup, etc)
mise.toml              ─ tool versions + tasks for every stack in here
.env                   ─ single source of truth for every var, every app
```

Workspace tooling lives at the root: `mix.exs` + `.workspace.exs` + `workspace.lock` for the Elixir apps; `Cargo.toml` (workspace) for the Rust crates; `pnpm-workspace.yaml` for the JS side. Each app/package has its own manifest underneath.

## Tooling — `mise`

[`mise`](https://mise.jdx.dev) pins Erlang, Elixir, Node, C++, pnpm, Rust, and the DuckDB CLI to the versions CI uses, and exposes every dev task. After `mise install` from this directory:

```sh
mise tasks                  # list everything available
mise run install            # one-time bootstrap across all stacks
mise run dev                # full Elixir stack: ngrok + both Phoenix apps
mise run core:dev           # full sf-voice stack: mysql + backend + frontend
mise run test               # workspace test runner
```

`mise` also auto-loads `.env` on `cd` into the repo, so every shell and every task starts from the same env without sourcing anything by hand.

---

## Installation

### Whole workspace

Requires the `mise` tools above plus Docker for the app stacks.

```sh
mise install      # install pinned language/tool versions
mise run install  # one-time bootstrap across all stacks
```

To run the core app after installation:

```sh
mise run core:dev
```

That opens:
- **Frontend** on http://localhost:3000 — landing on the public light-theme shell. 

- **Backend API** on http://localhost:8080 — `GET /healthz` for liveness, `GET /api/hello` for a sanity check.

### One SDK

Use the package for the language you are building in. Most examples only call
external APIs after you copy the example `.env.example` to `.env` and set
`SF_VOICE_API_KEY`. Package names follow the current manifests; if a package is
not published yet, use the linked folder as a local path dependency or build
artifact.

| language | package | how to use it |
| --- | --- | --- |
| TypeScript / JavaScript | [`@sf-voice/media`](ts/sdk) | `pnpm add @sf-voice/media@0.1.1` or `npm install @sf-voice/media@0.1.1` |
| Python | [`sf-voice-media`](python) | `pip install sf-voice-media==0.1.1` |
| Go | [`github.com/sf-voice/sf-voice-media-go`](go) | `go get github.com/sf-voice/sf-voice-media-go@v0.1.1` |
| Rust | [`sf_voice_media`](rust) | `cargo add sf_voice_media@0.1.1` |
| C++ | [`cpp/`](cpp) | use Conan package `sf_voice/0.1.1` or include this repo's `cpp/` package from your CMake build |
| Java | [`java/`](java) | build the local jar with `(cd java && gradle jar)`, then depend on `com.sfvoice:sf-voice-media-java:0.1.1` |
| Kotlin | [`kotlin/`](kotlin) | build the local jar with `(cd kotlin && gradle jar)`, then depend on `com.sfvoice:sf-voice-media-kotlin:0.1.1` |
| Elixir | [`elixir/sf_voice`](elixir/sf_voice) | add `{:sf_voice, "~> 0.1.1"}` to `deps` |

## Language Examples

Start with the full examples index in [`apps/EXAMPLES.md`](apps/EXAMPLES.md).

| language | example | what it shows |
| --- | --- | --- |
| TypeScript / JavaScript | [`apps/fifteenlabs`](apps/fifteenlabs), [`apps/fraud-prototype`](apps/fraud-prototype) | browser ingest/search demo and phone-line fraud prototype |
| Python | [`apps/cohere`](apps/cohere) | sync and async SDK CLI usage |
| Go | [`apps/livecart`](apps/livecart) | ingest, poll, search, asset listing, and soft delete |
| C++ | [`apps/chips`](apps/chips) | CMake CLI demo with local or fetched C++ dependencies |
| Java | [`apps/sf-voice/java-example`](apps/sf-voice/java-example) | Spring Boot REST proxy using the Java SDK |
| Kotlin | [`apps/sf-voice/kotlin-example`](apps/sf-voice/kotlin-example) | Ktor REST proxy using the Kotlin SDK |
| Rust | [`rust`](rust) | SDK source package; no standalone app example yet |
| Elixir | [`elixir/sf_voice`](elixir/sf_voice) | SDK installation and usage examples |
