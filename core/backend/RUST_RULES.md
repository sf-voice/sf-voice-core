# Rust / axum / tokio rules

Shared conventions for `core/backend/*`. Read this **in addition to** [`AGENTS.md`](AGENTS.md) before working in any Rust crate here.

AGENTS.md owns project rules (ORM choice, schema source of truth, `AppError` shape, tracing, `org_id` everywhere, BINARY(16) IDs). This file owns stack / language conventions — `unsafe`, `.unwrap()`, async, axum, SeaORM call shapes — things that would be true on any axum + tokio service we'd write next.

---

## Stack — pinned choices

| Concern | Choice | Notes |
|---|---|---|
| Web framework | `axum 0.7` | with `tower-http` for cors / trace |
| Runtime | `tokio 1` (`features = ["full"]`) | multi-threaded scheduler |
| ORM | `sea-orm 2.0` (RC) | see AGENTS.md for usage rules |
| HTTP client | `reqwest 0.12` | `default-features = false`, `rustls-tls` |
| TLS | `rustls` everywhere | never `native-tls` / `openssl` — keeps the runner image small and avoids the openssl-sys headache |
| Errors (binary) | `thiserror` + `AppError` | one enum per crate; see AGENTS.md |
| Errors (scripts / `main`) | `anyhow` | bin entrypoints and tests only |
| Logging | `tracing` + `tracing-subscriber` | structured fields, not string concat |
| JSON | `serde` + `serde_json` | derive everywhere; no `serde_derive` directly |
| UUIDs | `uuid v7` | time-ordered; mapped to `BINARY(16)` per AGENTS.md |

Don't introduce a second crate for the same concern (e.g. `tokio-postgres` alongside SeaORM, `hyper` directly alongside axum, `chrono` + `time` for the same purpose). If the existing choice doesn't fit, replace it — don't stack.

When adding any new dep, pass it through this filter: (1) does the workspace already cover this? (2) is it `rustls`-compatible? (3) is `default-features = false` viable? (4) is there a lighter alternative in the std / tokio / tower trees?

---

## Unsafe & unwrap

These are the two escape hatches Rust gives you for "I know better than the type system." When that's true it's fine; when it's wrong the program panics or invokes UB. The default is to use the type system, not bypass it.

- **Avoid `unsafe { … }` blocks** unless there's a documented reason — FFI, proven-safe transmute, a performance-critical path with comments.
- **Avoid `.unwrap()` and `.expect()` in production code paths.** Use `?`, `match`, `unwrap_or`, `ok_or_else`, etc. Tests and one-shot scripts may use `.unwrap()` freely — failure there is the right behaviour.
- **When `unsafe` or `unwrap` is justified, leave a one-line comment** saying why so reviewers don't flag it.

Rejected alternatives: a hard-no rule (would fight legitimate FFI use in `aws*.rs` and similar), and a "use `expect` with a clear message" carve-out (still panics in prod).

---

## Async & Tokio

- **Never block in an async function.** No `std::fs`, no `std::thread::sleep`, no synchronous database drivers, no CPU-heavy loops. Wrap in `tokio::spawn_blocking` when unavoidable.
- **Never hold a lock across `.await`.** Take what you need, drop the guard (an explicit `drop(guard);` or block scope), then await. Deadlocks here are invisible until prod.
- **Prefer channels over shared mutable state.** `tokio::sync::mpsc` for one-to-one, `broadcast` for fan-out, `watch` for single-value rolling state. Reach for `Arc<Mutex<T>>` only when the data genuinely is shared mutable state with no producer/consumer shape (the duckdb connection in `state.rs` is the example).
- **Bounded channels by default.** Unbounded means OOM under backpressure. Pick a size based on tolerable lag and stick a comment explaining it.
- **Spawned tasks need `'static + Send`.** If a future doesn't satisfy that, refactor — don't reach for `LocalSet` unless single-threaded execution is a real requirement.
- **`select!` is the structured-concurrency primitive.** Use it for "first of many" + cancellation; document which branch wins on a tie.
- **Fire-and-forget needs a justification comment.** Default to keeping the `JoinHandle` and awaiting (or logging) the result. Untracked `tokio::spawn` calls are how you ship orphaned errors.

---

## Axum handlers

- **Handler signature:** `async fn name(extractors..., State(state): State<AppState>, body) -> Result<impl IntoResponse, AppError>`. Always `Result<_, AppError>` (the no-panic rule lives in AGENTS.md → Errors and tracing).
- **Extractor order is enforced by the framework.** `FromRequestParts` (Path, Query, State, AuthContext, headers, cookies) come first; **at most one** `FromRequest` body extractor (`Json<T>`, `Form<T>`, `Bytes`) and it must be last. Getting this wrong is a compile error, but the message is opaque — knowing the rule shortens the debug.
- **Custom extractors use `#[async_trait]`.** axum-core 0.4 wraps the trait, so impls must too. Pattern is in `middleware.rs::FromRequestParts for AuthContext`.
- **`State<AppState>` is cheap to clone.** `AppState` itself is `Clone` and holds `Arc`s / `DatabaseConnection` (already internally `Arc`'d). Don't wrap it in another `Arc`.
- **Substates via `FromRef`.** When a route only needs `state.orm`, extract just that — handlers shouldn't depend on the whole `AppState` just to reach one field, but don't add a substate before there are two consumers.
- **Middleware composes via `tower::Layer`.** `Router::layer(...)` for global, `Router::route_layer(...)` for scoped. Request order = declaration order; response order = reverse.
- **Auth middleware is permissive; handlers gate.** `maybe_auth` attaches `AuthContext` when valid and passes through when not; the `AuthContext` extractor itself is what produces 401. Mirror that shape for any new auth-adjacent context (admin, scoped tokens, etc.).

---

## Errors

AGENTS.md already locks in `AppError` + `IntoResponse` + no panics on the request path. Additions:

- **Add a variant when the http status is new.** Otherwise route through `AppError::Internal(String)`. Don't grow the enum for ergonomics.
- **Use `#[from]` for conversions you want implicit.** Library errors that always map to the same response (sqlx, reqwest, duckdb) get `#[from]`. Errors that need context (a parse failure with a field name) get an explicit `.map_err(...)` at the call site so the message carries the context.
- **`anyhow::Result` is for `main` and tests.** Never expose `anyhow::Error` across a public crate boundary. Inside `main.rs` and `bin/*.rs` it's fine for boot-time failures.
- **`?` is the default propagation.** `match` only when the branches do meaningfully different things; if every arm just returns the error, you wanted `?`.
- **Log at the boundary, not at every layer.** `IntoResponse` for `AppError` already logs server errors via `tracing::error!`. Don't re-log on the way up.

---

## SeaORM patterns

These extend AGENTS.md → "ORM and database access" with shape rules.

- **`entities::<table>::Entity::find()` is the entry point.** Chain `.filter(Column::X.eq(v))`, `.order_by(...)`, `.one(&state.orm)` / `.all(&state.orm)`.
- **`Uuid` ↔ `Vec<u8>` conversion lives at the call site.** AGENTS.md → BINARY(16) IDs sets the storage rule; the shape is `id.as_bytes().to_vec()` going in and `Uuid::from_slice(&row.id)` coming out. Wrap the `from_slice` error in `AppError::Internal` — a malformed id from the DB is a real bug.
- **`org_id` predicate in every query** — see AGENTS.md → Scope flag. The only exception is `/healthz`-style endpoints with no per-tenant data; if you find yourself writing a query without one, prove it should be exempt.
- **Transactions via `state.orm.begin().await?`.** Pass `&txn` (or `&mut *txn`) to entity calls inside the block. Commit explicitly; the drop is a rollback.
- **No `.unwrap()` on `.one(...)`.** That returns `Option`; the unwrap rule above applies. Use `.ok_or(AppError::NotFound)?` or `let Some(...) = ... else { return Err(...); };`.

---

## Naming & types

- **`snake_case`** for files, modules, functions, variables; **`CamelCase`** for types, traits, enums; **`SCREAMING_SNAKE_CASE`** for consts.
- **Method-name conventions matter for readers.** `as_x` (cheap reference cast), `to_x` (cheap-ish copy), `into_x` (consuming conversion). Don't mix them.
- **Newtype over `String` / `Uuid`** when a value carries an invariant — e.g. `OrgId(Uuid)`, `SessionToken([u8; 32])`. Cheap to add, hard to add later.
- **Derive `Debug, Clone` on every public struct unless you have a reason not to.** `Copy` only for small (≤ 16 bytes) value types with no heap data. Manually impl `Debug` if a field is secret (passwords, tokens, encryption keys).
- **`pub(crate)` by default.** Reach for `pub` only when an item actually crosses a crate boundary. `mod.rs` is gone — use `module_name.rs` siblings (already the convention here).

---

## Comments & docs

CLAUDE.md owns the voice rules (lowercase, mimic tone, WHY not WHAT). Stack-specific:

- **`//!` for module-level docs** at the top of each `.rs` file. One paragraph: what this module owns and what its contract is. `main.rs` and `state.rs` here are the model.
- **`///` for public items.** Function / struct / enum variant. Tell the reader what changes externally on success and what kinds of `AppError` can come out. If the body is one obvious line, skip the doc.
- **No example blocks for internal items.** Doctests in a binary crate cost compile time and don't ship to users. Save examples for crates we publish.
- **Reference the rule, not the lore.** `// see AGENTS.md "no raw SQL"` is fine; `// added 2026-05-12 after the bug in ticket 134` rots.

---

## Lints, formatting, pre-commit

- **`cargo fmt --all`** before committing. No exceptions.
- **`cargo clippy --workspace --all-targets -- -D warnings`** before committing. Treat clippy warnings as errors locally; only `#[allow(clippy::...)]` with a one-line reason.
- **`cargo check --workspace --all-targets`** beats `cargo build` for the inner loop — same type checking, no codegen.
- **Don't suppress lints to make tests pass.** Fix the test or fix the lint trigger.

---

## Testing

- **Unit tests live at the bottom of the file** in `mod tests { ... }` with `#[cfg(test)]`. Same file = same change unit, easier to keep in sync.
- **Integration tests live in `<crate>/tests/`.** One file per feature surface; each gets its own binary, so name them by what they cover (`tests/auth_flow.rs`, not `tests/test1.rs`).
- **`#[tokio::test]`** for async tests. Add `flavor = "multi_thread"` only when the test genuinely needs it (the default is fine for almost everything).
- **DB tests use a real MySQL.** AGENTS.md → "no mocks across the SeaORM boundary" applies; spin up the `db:start` container and run against it. Wrap each test in a transaction that rolls back if you can; otherwise use unique org_ids per test.
- **`cargo nextest run`** if it's installed locally — faster than `cargo test`. CI sticks with `cargo test` until we standardise.

---

## What goes where

- **One concept per file at the crate root.** `auth.rs`, `aws.rs`, `encryption.rs`, `events.rs`, `vad.rs` — current shape. Don't create `mod.rs` style folders for two items; flatten until a folder genuinely earns three or more siblings (`routes/`, `jobs/`).
- **`models.rs`** is request / response DTOs only — anything an axum handler serialises. Entities (DB rows) live in the `entities` crate per AGENTS.md.
- **`state.rs`** holds `AppState` and nothing else. Resist the urge to put helpers there.
