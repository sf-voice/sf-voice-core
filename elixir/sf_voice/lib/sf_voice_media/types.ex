defmodule SfVoiceMedia.Types do
  @moduledoc """
  typespecs for all request and response shapes in the sf-voice media API.

  these are documentation-only types — Elixir maps are used at runtime.
  all keys are atoms (the HTTP layer atomises string keys via `Req`'s JSON decode).
  """

  # ── shared ───────────────────────────────────────────────────────────────────

  @typedoc "ingestion source — where the media file comes from"
  @type source :: :url | :s3

  @typedoc "media kind"
  @type media_type :: :video | :audio

  @typedoc "lifecycle state of a task or asset"
  @type task_status :: :pending | :indexing | :ready | :failed

  @typedoc "what kind of match a search result represents"
  @type match_type :: :visual | :conversation | :text_in_video

  # ── pagination ───────────────────────────────────────────────────────────────

  @typedoc """
  pagination envelope returned by list and search endpoints.

      %{total: integer, page: integer, limit: integer, next_page_token: String.t() | nil}
  """
  @type page_info :: %{
          total: non_neg_integer(),
          page: pos_integer(),
          limit: pos_integer(),
          next_page_token: String.t() | nil
        }

  # ── asset ────────────────────────────────────────────────────────────────────

  @typedoc "a single asset stored in the library"
  @type asset :: %{
          id: String.t(),
          media_type: media_type(),
          source_type: source(),
          status: task_status(),
          metadata: map() | nil,
          duration_ms: non_neg_integer() | nil,
          created_at: String.t(),
          updated_at: String.t()
        }

  # ── ingest ───────────────────────────────────────────────────────────────────

  @typedoc """
  request body for `POST /v1/ingest`.

  either `:url` (with `:url` key) or `:s3` (with `:s3_key` key).
  `:media_type` and `:metadata` are optional for both.
  """
  @type ingest_request :: %{
          required(:source) => source(),
          optional(:url) => String.t(),
          optional(:s3_key) => String.t(),
          optional(:media_type) => media_type(),
          optional(:metadata) => map()
        }

  @typedoc "202 response body from `POST /v1/ingest`"
  @type ingest_response :: %{
          asset_id: String.t(),
          task_id: String.t(),
          status: :pending
        }

  # ── tasks ────────────────────────────────────────────────────────────────────

  @typedoc "response from `GET /v1/tasks/:task_id`"
  @type task :: %{
          task_id: String.t(),
          asset_id: String.t(),
          status: task_status(),
          error: String.t() | nil,
          created_at: String.t(),
          completed_at: String.t() | nil
        }

  # ── list assets ──────────────────────────────────────────────────────────────

  @typedoc "optional query params for `GET /v1/assets`"
  @type list_assets_params :: %{
          optional(:page) => pos_integer(),
          optional(:limit) => pos_integer()
        }

  @typedoc "response from `GET /v1/assets`"
  @type asset_list_response :: %{
          items: [asset()],
          page_info: page_info()
        }

  # ── search ───────────────────────────────────────────────────────────────────

  @typedoc "request body for `POST /v1/search`"
  @type search_request :: %{
          required(:query) => String.t(),
          optional(:types) => [match_type()],
          optional(:asset_ids) => [String.t()],
          optional(:threshold) => float(),
          optional(:page) => pos_integer(),
          optional(:limit) => pos_integer()
        }

  @typedoc "a single match returned by the search endpoint"
  @type search_result :: %{
          asset_id: String.t(),
          score: float(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer(),
          match_type: match_type(),
          thumbnail_url: String.t() | nil
        }

  @typedoc "response from `POST /v1/search`"
  @type search_response :: %{
          results: [search_result()],
          page_info: page_info()
        }

  # ── poll_task opts ───────────────────────────────────────────────────────────

  @typedoc """
  options for `SfVoiceMedia.poll_task/3`.

  - `:interval_ms` — milliseconds between polls (default 1_500)
  - `:timeout_ms`  — max total wait time in ms before raising (default 120_000)
  """
  @type poll_opts :: %{
          optional(:interval_ms) => pos_integer(),
          optional(:timeout_ms) => pos_integer()
        }
end
