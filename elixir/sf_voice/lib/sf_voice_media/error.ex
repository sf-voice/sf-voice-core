defmodule SfVoiceMedia.Error do
  @moduledoc """
  structured error returned by every SDK function on failure.

  raised as an exception by `SfVoiceMedia.poll_task/3` on timeout or task failure;
  returned inside `{:error, %SfVoiceMedia.Error{}}` tuples by all other functions.

  fields:
  - `code`    — machine-readable error code string from the API (e.g. `"not_found"`)
  - `message` — human-readable description
  - `status`  — http status code, or `nil` when the error is client-side (e.g. poll timeout)
  """

  defexception [:code, :message, :status]

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          status: non_neg_integer() | nil
        }

  @impl true
  def message(%__MODULE__{code: code, message: msg, status: status}) do
    "[#{code}] #{msg} (HTTP #{status})"
  end

  # ── constructors ─────────────────────────────────────────────────────────────

  @doc """
  builds an `Error` from the standard API error envelope:
  `%{"error" => %{"code" => ..., "message" => ...}}`.

  falls back gracefully when the body is missing or malformed.
  """
  @spec from_response(non_neg_integer(), map() | nil) :: t()
  def from_response(status, %{"error" => %{"code" => code, "message" => msg}}) do
    %__MODULE__{code: code, message: msg, status: status}
  end

  def from_response(status, _body) do
    %__MODULE__{
      code: "http_error",
      message: "request failed with status #{status}",
      status: status
    }
  end

  @doc """
  builds a client-side timeout error (no http status).
  """
  @spec poll_timeout(String.t(), non_neg_integer()) :: t()
  def poll_timeout(task_id, timeout_ms) do
    %__MODULE__{
      code: "poll_timeout",
      message: "task #{task_id} did not complete within #{timeout_ms}ms",
      status: nil
    }
  end
end
