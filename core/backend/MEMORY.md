# core/backend/MEMORY.md

Decisions specific to `core/backend`.

Repo-wide conventions live in repo-root `AGENTS.md`. Product spec lives in [`AGENTS.md`](AGENTS.md).

Read this file before doing any work in `core/backend`.

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
