defmodule EllieAi.EnvCheck do
  @moduledoc """
  validates required env vars at boot. prints a single clean banner with
  every missing var (not one stacktrace per missing var) and halts the vm
  before the supervisor starts so we don't drown the screen in restart spam.

  skipped in :test so the suite doesn't have to set bogus values.
  """

  # {name, scope, description}
  #   :always — required in every non-test env (dev + prod)
  #   :prod   — required only when running a prod release
  #
  # things with a sensible dev fallback in runtime.exs (INTERNAL_API_TOKEN
  # → placeholder, RESTO_BASE_URL → localhost) are :prod-only here so dev
  # boots without ceremony. anything that breaks at runtime in dev when
  # missing (no fallback possible) is :always.
  @vars [
    {"INTERNAL_API_TOKEN", :prod, "shared bearer between resto and ellie."},
    {"RESTO_BASE_URL", :prod, "base url for resto's /api."},
    {"SECRET_KEY_BASE", :prod, "phoenix endpoint signing key. generate with `mix phx.gen.secret`."},
    {"DATABASE_PATH", :prod, "absolute path to ellie's sqlite file (e.g. /etc/ellie_ai/ellie_ai.db)."},
    {"PHX_HOST", :prod, "public hostname (e.g. ellie-ai.sf-voice.sh)."},
    # F4 (eng review 2026-05-10): without this, AudioBridge returns :ignore
    # and the call tree boots without an audio bridge — caller hears silence
    # on a connected line. fail boot, don't degrade.
    {"OPENAI_API_KEY", :always, "openai api key for the realtime voice session."},
    {"TELNYX_API_KEY", :prod, "telnyx api key for outbound call control."},
    {"TELNYX_PUBLIC_KEY", :prod, "telnyx ed25519 public key — verifies inbound webhook signatures."},
    {"PHONE_NUMBER", :prod, "telnyx number ellie answers calls on (E.164)."},
    {"STAFF_PHONE_E164", :prod, "fallback staff phone for escalation (E.164)."},
    {"S3_BUCKET_NAME", :prod, "s3 bucket for call recording archive (e.g. sf-voice-demo-calls)."},
    {"AWS_ACCESS_KEY_ID", :prod, "aws access key id (s3 + ses)."},
    {"AWS_SECRET_ACCESS_KEY", :prod, "aws secret access key."},
    {"AWS_REGION", :prod, "aws region (e.g. us-west-1)."}
  ]

  @doc """
  validates env. returns :ok or halts the vm with status 1 after printing a
  banner of missing vars.
  """
  def validate! do
    case current_env() do
      :test -> :ok
      env -> check!(env)
    end
  end

  defp check!(env) do
    missing =
      @vars
      |> Enum.filter(fn {name, scope, _desc} ->
        required_here?(scope, env) and blank?(System.get_env(name))
      end)

    case missing do
      [] -> :ok
      vars -> halt!(env, vars)
    end
  end

  defp required_here?(:always, _env), do: true
  defp required_here?(:prod, :prod), do: true
  defp required_here?(_, _), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp halt!(env, missing) do
    IO.puts(:stderr, """

    ╭─ ellie_ai: missing required env vars (#{env}) ───────────────────────────
    │
    #{Enum.map_join(missing, "\n", fn {name, _scope, desc} -> "│  • #{name}\n│      #{desc}" end)}
    │
    │  set them in the root .env (see .env.example for the template) and retry.
    ╰──────────────────────────────────────────────────────────────────────────

    """)

    System.halt(1)
  end

  # mix is loaded in dev/test but not in releases. release artifacts have
  # RELEASE_NAME set, which we treat as prod.
  defp current_env do
    cond do
      Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) -> Mix.env()
      System.get_env("RELEASE_NAME") -> :prod
      true -> :prod
    end
  end
end
