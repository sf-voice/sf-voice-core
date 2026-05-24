defmodule Mix.Tasks.EllieAi.Scammer do
  @moduledoc """
  place an outbound scammer-AI call to the operator's phone for
  fraud-detection prototype testing.

      mix ellie_ai.scammer --script irs
      mix ellie_ai.scammer --script fake_bank_fraud --to +15551234567

  options:
    * `--script` (required) — one of `EllieAi.Scammer.Scripts.ids/0`.
    * `--to` — E.164 number to dial. defaults to `FRAUD_ALERT_PHONE_E164`.

  requires the running app — boots the OTP app, runs the dial, and
  exits. the call itself continues in the supervision tree until the
  user hangs up or the fraud detector intervenes.

  to abort an in-progress test call: say `"STOP TEST"` on the line. the
  detector hard-codes that phrase to a fraud-score of 1.0 which forces
  an immediate hangup of the scammer leg.
  """

  use Mix.Task

  @shortdoc "Dial an outbound scammer-AI test call"

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [script: :string, to: :string],
        aliases: [s: :script, t: :to]
      )

    script_id =
      case Keyword.get(opts, :script) do
        nil ->
          Mix.raise(
            "--script is required. available: #{Enum.map_join(EllieAi.Scammer.Scripts.ids(), ", ", &to_string/1)}"
          )

        s ->
          to_atom_or_raise(s)
      end

    to =
      Keyword.get(opts, :to) ||
        System.get_env("FRAUD_ALERT_PHONE_E164") ||
        Mix.raise("no --to and FRAUD_ALERT_PHONE_E164 not set")

    Mix.Task.run("app.start")

    case EllieAi.Scammer.dial(to, script_id) do
      {:ok, ccid} ->
        Mix.shell().info("scammer dial started: ccid=#{ccid} to=#{to} script=#{script_id}")
        Mix.shell().info("say \"STOP TEST\" on the call to abort.")

      {:error, reason} ->
        Mix.raise("scammer dial failed: #{inspect(reason)}")
    end
  end

  defp to_atom_or_raise(s) do
    id =
      try do
        String.to_existing_atom(s)
      rescue
        ArgumentError ->
          Mix.raise(
            "unknown script: #{inspect(s)}. available: #{Enum.map_join(EllieAi.Scammer.Scripts.ids(), ", ", &to_string/1)}"
          )
      end

    unless id in EllieAi.Scammer.Scripts.ids() do
      Mix.raise(
        "unknown script: #{inspect(s)}. available: #{Enum.map_join(EllieAi.Scammer.Scripts.ids(), ", ", &to_string/1)}"
      )
    end

    id
  end
end
