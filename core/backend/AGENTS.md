# core/backend — sf-voice debugging API

Rules and conventions only. Detail and implementation plan live in [`plan/`](plan/).

## Scope flag

Multi-tenant by design. The "single restaurant" rule from `apps/*` does **not** apply here. sf-voice's external customers each get an org. Every queryable row carries `org_id` and every query filters on it.

## ORM and database access

1. **One ORM: SeaORM 2.0.** No `sqlx::query!` / `sqlx::query_as!` in handlers, jobs, or middleware. New code reaches `state.orm: sea_orm::DatabaseConnection` and uses entity-typed queries via the `entities` crate.
2. **No raw SQL.** The only place raw SQL is allowed is `core/backend/entities/src/lib.rs::apply_extras`, for DDL the schema-sync builder can't express (column-prefix indexes, FULLTEXT, `ON UPDATE CURRENT_TIMESTAMP`).
3. **Schema source of truth: `core/backend/entities/`.** One Rust file per table. Tables, columns, foreign keys, unique indexes are reconciled from there at api boot via `db.get_schema_registry("entities::*").sync(&db)`.
4. **No ENUM columns.** Every state/role/kind column is `String` mapped to `VARCHAR(N)` with `#[sea_orm(comment = "'a' | 'b' | 'c'")]` listing allowed values. Validation happens in Rust types, not at the DB layer.
5. **`BINARY(16)` IDs.** Mapped to `Vec<u8>` in entities; convert to/from `Uuid` at the application boundary.
6. **Edit entities, not DDL.** Schema-sync handles ADDs (table, column, FK, unique). For non-additive changes (DROP, type change) hand-write a one-off SQL block in `apply_extras` and update the entity.

## Errors and tracing

- `AppError` enum with `IntoResponse`; never panic on a request path.
- `tracing` + `tracing-subscriber`. Every job logs `job_id`, `org_id`, `kind` at every step.

## Workflow commands

| Command | What it does |
|---|---|
| `mise run api:dev` | Boot the api locally; schema-sync runs at startup. |
| `mise run db:migrate` | Run schema-sync without booting the api (`sf-voice-api --bin sync`). |
| `mise run db:start` / `db:stop` / `db:nuke` | dev mysql container lifecycle. |

## Detail and rationale

- [`plan/service-overview.md`](plan/service-overview.md) — what this service is + the data stores wired in
- [`plan/v1-scope.md`](plan/v1-scope.md) — what's in v1, what's deferred
- [`plan/duckdb-vectors.md`](plan/duckdb-vectors.md) — embedded analytical store + HNSW
- [`plan/clickhouse-analytics.md`](plan/clickhouse-analytics.md) — high-cardinality telemetry (v2)
- [`plan/search-usecases.md`](plan/search-usecases.md) — query patterns mapped to schema
- [`plan/pipeline-contracts.md`](plan/pipeline-contracts.md) — VAD, Whisper, diarization, embeddings, slack
- [`plan/routes-v1.md`](plan/routes-v1.md) — http surface
- [`plan/runtime-conventions.md`](plan/runtime-conventions.md) — job runner, event broker, UUID handling
- [`plan/open-questions.md`](plan/open-questions.md) — known v2 design decisions
- [`plan/frontend-xref.md`](plan/frontend-xref.md) — contract points the frontend depends on
