# MEMORY.md

Permanent log of significant decisions about direction, architecture,
conventions, and strategy. Read this before making decisions that
might contradict prior ones; flag the conflict before acting.

Format per entry: date, decision, why, what was rejected.

---

## [2026-05-14] — Rust safety rules
**What was decided:**
- Avoid `unsafe { … }` blocks unless there's a documented reason (FFI,
  proven-safe transmute, performance-critical path with comments).
- Avoid `.unwrap()` and `.expect()` in production code paths. Use `?`,
  `match`, `unwrap_or`, `ok_or_else`, etc. Tests and one-shot scripts
  may use `.unwrap()` freely — failure there is the right behaviour.
- When `unsafe` or `unwrap` is justified, leave a one-line comment
  saying why so reviewers don't flag it.

**Why:** these are the two main escape hatches Rust gives you for "I
know better than the type system." When that's true it's fine; when
it's wrong the program panics or invokes UB. The default is to use
the type system, not bypass it.

**What was rejected:** a hard-no rule (would fight legitimate FFI use
in `core/backend/api/src/aws*.rs` and similar), and a "use `expect`
with a clear message" carve-out (still panics in prod).

---

## [2026-05-14] — SeaORM as the Rust ORM
**What was decided:** SeaORM (built on sqlx) for the control-plane
relational layer (`core/backend/api/`). Migrations ported from raw
`.sql` files into the SeaORM Rust migration crate; entities generated
via `sea-orm-cli generate entity` then refined.

**Why:** async-first matches Axum, sits on top of sqlx (which the
codebase already uses), supports first-class column comments via
`.comment("…")` in both migrations and entities, and has the largest
ecosystem of the async-Rust ORMs. Convex's choice of `mysql_async` was
ruled out because Convex is a database vendor with reasons that don't
transfer (custom multi-tenant routing, raw protocol control). For a
SaaS bookkeeping layer, sqlx + SeaORM gives strictly more for free.

**What was rejected:**
- Raw `mysql_async` — would mean re-implementing the connection pool,
  query builder, type mapping, and migration runner. No benefit for
  application code.
- Diesel + diesel-async — strongest types but mostly sync; async is a
  wrapper that's still maturing for MySQL. Two query mental models in
  one async codebase.
- Welds — too young for a project that's about to scale.
- Status quo (sqlx with runtime queries + manual `String` types) — no
  type safety on status/role/kind columns; typo-prone.

The data plane (S3 + Parquet + custom query engine) is independent;
this decision does not touch it.

---

## [2026-05-14] — No ENUM columns in MySQL
**What was decided:** all state/role/kind/status fields are
`VARCHAR(N)` with a leading SQL comment listing the allowed values,
e.g. `-- 'queued' | 'running' | 'done' | 'failed'`. Validation lives
in Rust domain types (typed enums that round-trip to/from the
VARCHAR string).

**Why:** MySQL `ENUM` values can only be added or removed via
`ALTER TABLE`, generating DDL noise in migration history and forcing
a deploy for every new state value. VARCHAR + comment + Rust enum on
the read side gives the same type safety with none of the rigidity.

**What was rejected:** `CHECK` constraints on the column (also require
ALTER to update), and an enforcement-free "everything is String"
posture (loses type safety in Rust).
