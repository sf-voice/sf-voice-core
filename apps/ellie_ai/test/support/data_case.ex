defmodule EllieAi.DataCase do
  @moduledoc """
  shared setup for tests that hit the database. each test runs inside a
  transaction that's rolled back at the end so they can run in parallel
  without stepping on each other's writes.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias EllieAi.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import EllieAi.DataCase
    end
  end

  setup tags do
    Req.Test.set_req_test_from_context(tags)
    Req.Test.verify_on_exit!()

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EllieAi.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc "extract changeset errors as a string-keyed map for assertions."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
