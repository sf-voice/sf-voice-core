# Runtime conventions

- **DB access — MySQL.** SeaORM 2.0 via the typed entities in `core/backend/entities/`. `DatabaseConnection` lives on `AppState.orm`. Schema reconciliation runs at boot via `db.get_schema_registry("entities::*").sync(&db)` followed by `entities::apply_extras(&db)`. No raw SQL anywhere outside `apply_extras`. (See AGENTS.md → "ORM and database access".)
- **DB access — DuckDB.** Single in-process `Connection` behind a mutex on `AppState`. Embeddings read/write happens in the transcribe job and the `/api/search` handler. Schema (incl. `vss` extension load) is created on startup if missing.
- **Job runner.** In-process tokio task that polls `jobs` table (`status='queued' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`). Single worker in v1. Documented constraint: single API node.
- **Event broadcast.** In-process `tokio::sync::broadcast` registry keyed by `job_id`. Each job-step append publishes; SSE handlers subscribe. Single-node constraint same as runner.
- **UUIDs.** v7 from the `uuid` crate. `BINARY(16)` columns in entities use `Vec<u8>`; convert to/from `Uuid` at the application boundary. DuckDB takes `UUID` natively.
- **Errors.** `AppError` enum with `IntoResponse`; never panic on a request path.
- **Tracing.** `tracing` + `tracing-subscriber`. Every job logs `job_id`, `org_id`, `kind` at every step.
