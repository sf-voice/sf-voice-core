# Elixir / Phoenix rules

Shared conventions for every BEAM app under `apps/`. Read this **in addition to** the app's own `AGENTS.md` before working in `apps/ellie_ai`, `apps/resto_booking_app`, or any future Elixir app.

App-specific behaviour, design rules, and product scope live in each app's own `AGENTS.md`.

---

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues.
- Use the already included and available `:req` (`Req`) library for HTTP requests. **Avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is the preferred HTTP client for Phoenix apps.
- **Shared constants live in a constants module.** When a literal value (domain enum, magic number with business meaning, regex, etc.) is used in **two or more modules**, extract it to a per-context `Constants` module — e.g. `RestoBookingApp.Reservations.Constants`. Cross-context shared values go in a top-level module (`RestoBookingApp.Validations`, etc.). Values used in only one module stay as `@module_attribute` co-located with the function that uses them. Do not preemptively centralise — wait for the second use.

  Existing examples: `RestoBookingApp.Reservations.Constants`, `RestoBookingApp.Menu.Constants`, `RestoBookingApp.Contacts.Constants`, `RestoBookingApp.Validations`, `EllieAi.Calls.Constants`.

  Caveats:
  - Pattern matches and Ecto schema-default literals (e.g. `field :status, :string, default: "ringing"`) keep their string literals — Elixir can't reference a function call in either position.
  - For `in` guards, read the constant once at compile time via a module attribute (`@roles Constants.roles()`), since guards reject runtime function calls.

  See `apps/MEMORY.md` (2026-05-10) for the decision history behind this rule.

---

## Phoenix guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content.
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again.
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`.
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed.
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module.
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar.
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors.
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">`) with your own values, no default classes are inherited, so your custom classes must fully style the input.

---

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**.

  **Never do this (invalid):**

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound. For block expressions like `if`, `case`, `cond`, etc., you *must* bind the result of the expression to a variable if you want to use it and you **cannot** rebind the result inside the expression:

      # INVALID: rebinding inside `if`; the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file — can cause cyclic dependencies and compilation errors.
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. Access struct fields directly (`my_struct.field`) or use higher-level APIs (`Ecto.Changeset.get_field/2` for changesets).
- Elixir's standard library has everything for date and time. Use `Time`, `Date`, `DateTime`, and `Calendar`. **Never** install additional dependencies unless asked or for date/time parsing (you can use the `date_time_parser` package).
- Don't use `String.to_atom/1` on user input (memory leak risk).
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards.
- OTP primitives like `DynamicSupervisor` and `Registry` require names in the child spec, e.g. `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`.
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. Pass `timeout: :infinity` most of the time.

---

## Background tasks (Task / Task.Supervisor)

Pick the right API based on (a) is the caller long-running, and (b) should a crash kill the caller?

| API | Linked to caller? | Use when |
|---|---|---|
| `Task.async/1` + `Task.await/2` | **Linked** — task crash kills caller | One-shot helper or test code. **Never inside a GenServer that should outlive the task.** |
| `Task.Supervisor.async_nolink/3` | **Not linked** — caller stays alive | Inside a GenServer firing background work (analytics, sentiment, slow I/O). Handle `{ref, result}` and `{:DOWN, ref, :process, _pid, _reason}` in `handle_info/2`. |
| `Task.Supervisor.start_child/2` | Not linked, no reply expected | Fire-and-forget. No reply, no monitoring. Result is discarded. |
| `Task.async_stream/3` | Linked stream | Concurrent enumeration with back-pressure (`max_concurrency`, `timeout: :infinity`). |

Rules:

1. **Never call `Task.async/1` from a long-running process** (GenServer, LiveView, supervised worker). The task is linked; a crash propagates up. Use `Task.Supervisor.async_nolink/3` instead.
2. **Every app that uses background tasks declares a `Task.Supervisor` in its application supervision tree**, with an explicit name:
   ```elixir
   {Task.Supervisor, name: MyApp.TaskSupervisor}
   ```
   Then `Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> ... end)` from the GenServer.
3. **Always handle the `{:DOWN, ref, :process, _pid, _reason}` message** in `handle_info/2` when using `async_nolink`. Silent failure of a task you started is a bug.
4. **No new bare `Task.async/1` in lib code.** If you see one in a long-running module, treat it as a refactor candidate.
5. **For pure fire-and-forget** (no caller cares about success/failure), use `Task.Supervisor.start_child/2`. Don't reach for `spawn/1`.

---

## Mix guidelines

- Read the docs and options before using tasks (`mix help task_name`).
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`.
- `mix deps.clean --all` is **almost never needed**. **Avoid** it unless you have good reason.

---

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests — guarantees cleanup between tests.
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests.
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

  - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages.

---

## Phoenix routing

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions. The `scope` provides the alias:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  The `UserLive` route points to the `AppWeb.Admin.UserLive` module.

- `Phoenix.View` is no longer needed or included with Phoenix. Don't use it.
