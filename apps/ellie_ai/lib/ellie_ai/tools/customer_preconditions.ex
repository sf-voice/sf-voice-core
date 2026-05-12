defmodule EllieAi.Tools.CustomerPreconditions do
  @moduledoc "shared guard used by reservation-write tools — caller must have a first_name ."

  import Ecto.Query

  alias EllieAi.{Calls, Repo}
  alias EllieAi.Customers.CustomerSummary

  @doc "return :ok if the caller for this ccid has a non-nil first_name."
  @spec check(String.t()) :: :ok | {:error, {:permanent, String.t()}}
  def check(ccid) when is_binary(ccid) do
    case Calls.get_by_ccid(ccid) do
      %{org_id: org_id, from_phone: from} when is_binary(from) ->
        case Repo.one(
               from(c in CustomerSummary,
                 where: c.org_id == ^org_id and c.phone_e164 == ^from,
                 select: c.first_name
               )
             ) do
          fname when is_binary(fname) and fname != "" ->
            :ok

          _ ->
            {:error,
             {:permanent,
              "ask the caller for their name and call upsert_customer before booking, modifying, or cancelling a reservation"}}
        end

      _ ->
        {:error, {:permanent, "no active call context for this tool"}}
    end
  end
end
