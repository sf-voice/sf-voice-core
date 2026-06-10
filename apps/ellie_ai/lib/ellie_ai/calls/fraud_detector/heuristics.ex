defmodule EllieAi.Calls.FraudDetector.Heuristics do
  @moduledoc """
  pure regex/keyword scoring over a call transcript. no I/O, no Memory.
  scores in 0..1 with a list of matched rule labels for evidence.

  the `STOP_TEST` rule is special — it is a hard `1.0` operator override
  so that even if the LLM scammer ignores its in-prompt safety hatch the
  responder still fires and hangs up.
  """

  alias EllieAi.Calls.Constants

  @type score :: float()
  @type rule_label :: atom()

  # `{Regex, weight, label}`. weights sum-clamped to 1.0. order does not
  # matter — scoring evaluates every rule.
  @rules [
    # operator safety hatch — full weight, always wins.
    {~r/\bSTOP\s+TEST\b/i, 1.0, :operator_stop},

    # payment-method tells — strong fraud signal regardless of speaker.
    {~r/\bgift\s*cards?\b/i, 0.7, :gift_cards},
    {~r/\b(google|apple|itunes|steam|amazon|target|walmart)\s+(card|gift)/i, 0.7,
     :branded_gift_card},
    {~r/\bwire\s+(transfer|funds?|money)/i, 0.6, :wire_transfer},
    {~r/\b(bitcoin|btc|crypto(currency)?|usdt|tether|stable\s*coin)/i, 0.55, :crypto},
    {~r/\bwestern\s+union|moneygram\b/i, 0.7, :money_remit},

    # authority/agency impersonation.
    {~r/\b(irs|tax\s+(office|authority|department))\b/i, 0.6, :irs},
    {~r/\bsocial\s+security|ssn\b/i, 0.55, :ssn},
    {~r/\b(warrant|criminal\s+(charges|complaint))\b/i, 0.7, :warrant_threat},
    {~r/\b(officer|agent|inspector|detective)\s+[a-z]{3,}\b/i, 0.25, :authority_title},
    {~r/\b(microsoft|apple|google|amazon)\s+(security|support|technician)/i, 0.55,
     :fake_tech_support},
    {~r/\bcustoms\s+(officer|department|hold|duty)/i, 0.55, :customs},
    {~r/\b(your\s+)?(bank|fraud)\s+(department|team)\b/i, 0.4, :fake_bank_dept},

    # urgency / secrecy / social-engineering markers.
    {~r/\bdo(n'?t|\s+not)\s+(tell|hang\s+up|talk\s+to)/i, 0.5, :urge_secrecy},
    {~r/\b(immediately|right\s+now|within\s+the\s+next\s+(hour|few\s+minutes|minutes))\b/i,
     0.35, :urgency},
    {~r/\bstay\s+on\s+the\s+(line|phone)\b/i, 0.45, :keep_on_line},
    {~r/\bremote\s+(desktop|access|control)|anydesk|teamviewer|ammyy/i, 0.7, :remote_access},

    # victim-side compliance markers.
    {~r/\bi'?ll\s+go\s+buy\b/i, 0.55, :victim_buy_intent},
    {~r/\bhere'?s\s+the\s+(card\s+)?(number|code)/i, 0.7, :victim_reads_card},

    # grandparent / family-emergency tells.
    {~r/\b(your\s+)?(grandson|granddaughter|nephew|niece)\b/i, 0.4, :family_emergency},
    {~r/\b(bail|jail|posted\s+bond)\b/i, 0.45, :bail_jail}
  ]

  @doc """
  score a string or a full transcript (`[{role, text, at}]`). returns
  `{combined_score, matched_labels}` where combined_score is `max(rule_weights)`
  over all triggered rules — single strong rule is enough.
  """
  @spec score(String.t() | [{String.t(), String.t(), DateTime.t()}]) ::
          {score(), [rule_label()]}
  def score(text) when is_binary(text) do
    matches =
      Enum.flat_map(@rules, fn {re, weight, label} ->
        if Regex.match?(re, text), do: [{weight, label}], else: []
      end)

    case matches do
      [] -> {0.0, []}
      hits -> {hits |> Enum.map(&elem(&1, 0)) |> Enum.max(), Enum.map(hits, &elem(&1, 1))}
    end
  end

  def score(turns) when is_list(turns) do
    joined =
      Enum.map_join(turns, "\n", fn
        {role, text, _at} -> "#{role}: #{text}"
        {role, text} -> "#{role}: #{text}"
        text when is_binary(text) -> text
        _ -> ""
      end)

    score(joined)
  end

  @doc "true if the latest turn alone contains the operator stop phrase."
  @spec stop_test?(String.t()) :: boolean()
  def stop_test?(text) when is_binary(text) do
    String.contains?(String.upcase(text), Constants.stop_test_phrase())
  end

  def stop_test?(_), do: false

  @doc "rule list — exposed for tests."
  def rules, do: @rules
end
