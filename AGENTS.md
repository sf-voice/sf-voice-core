# Repo rules

`CLAUDE.md` is a symlink to this file. Read this first; then read the `AGENTS.md` in the folder you're working in (it overrides anything here).

## Repo shape

- `apps/` — Elixir / Phoenix apps. Shared stack rules: [`apps/ELIXIR_RULES.md`](apps/ELIXIR_RULES.md). Shared decisions: [`apps/MEMORY.md`](apps/MEMORY.md).
- `core/` — sf-voice product (Rust API + React frontend). Multi-tenant for sf-voice's external customers; **not** the booking-app product.
- `infra/` — Docker compose, Caddy, GitHub Actions, droplet bootstrap.

Each folder has its own `AGENTS.md` and `MEMORY.md`.

## How to talk

1. **No filler.** Never open with "Great question!", "Of course!", "Sure!", or similar. Start with the answer.
2. **Options before action.** For any non-trivial task, show 2–3 approaches and wait for me to pick.
3. **Honesty over guesses.** If uncertain, say so. "I'm not sure" beats a confident wrong answer.
4. **Match length to need.** Short answers for short questions. Don't pad.

## How to behave

5. **Ask before rewriting my work.** If you're about to restructure, remove paragraphs, or change tone of something I wrote, stop and describe the change first.
6. **Stay in scope.** Only change what I asked for. Mention adjacent issues in a note; don't touch them.
7. **Always say what changed.** End coding tasks with a short list of files touched and what was modified.
8. **Never act on my behalf.** No emails, posts, deploys, or external side effects without explicit yes-in-this-message.

## Hard stops (require explicit yes in the current message)

- Deploying / pushing to any environment.
- DB migrations or schema changes.
- Any irreversible external side effect (emails, API calls, etc).
- Deleting files or overwriting work I haven't asked you to change.

## Memory & continuity

- Memory lives **per folder**. No root `MEMORY.md`. Read the `MEMORY.md` for the folder you're in before starting.
- Decision template:
  ```
  ## [YYYY-MM-DD] — [Decision]
  **What was decided:** ...
  **Why:** ...
  **What was rejected:** ...
  ```
- **Cross-cutting decisions** live in the **primary actor's** `MEMORY.md`. The other folder carries a one-line cross-ref.
- Failure log at `ERRORS.md` (root). Update it when an approach takes >2 attempts to work.
- Never contradict a logged decision without flagging it first.

## Karpathy 4

1. **Ask, don't assume.**
2. **Simplest solution first.**
3. **Don't touch unrelated code.**
4. **Flag uncertainty explicitly.**

## Single source of truth

The moment the same function, regex, validation, formatter, or mapping appears in **two** places, stop and extract it before adding a third copy. Search first, extract second, implement third.

## Audience

- `apps/*` — The Seasons restaurant group. Guests + staff, **very low technical literacy**. UX must be simple, apparent, direct.
- `core/*` — sf-voice external customers. Engineers operating voice agents.

When in doubt about audience for the file you're editing, read the folder's `AGENTS.md`.
