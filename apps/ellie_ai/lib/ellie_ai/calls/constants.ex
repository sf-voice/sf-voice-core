defmodule EllieAi.Calls.Constants do
  @moduledoc """
  canonical call statuses, roles, mediums, and tool-call enums used by
  schemas and the surfaces that read/write them. schema-level defaults
  and pattern matches keep their string literals — Elixir can't call
  functions there.
  """

  # `missed` replaces the planned missed_calls table.
  def status_ringing, do: "ringing"
  def status_active, do: "active"
  def status_ended, do: "ended"
  def status_escalated, do: "escalated"
  def status_missed, do: "missed"

  def statuses,
    do: [
      status_ringing(),
      status_active(),
      status_ended(),
      status_escalated(),
      status_missed()
    ]

  # `staff` turns are written only by the /calls/:id sms composer, never the AI.
  def role_user, do: "user"
  def role_assistant, do: "assistant"
  def role_staff, do: "staff"
  def roles, do: [role_user(), role_assistant(), role_staff()]

  # direction is derived from (role, medium, call.channel_id); not stored.
  def medium_voice, do: "voice"
  def medium_sms, do: "sms"
  def mediums, do: [medium_voice(), medium_sms()]

  # channel_id format: tel_<caller>_<callee>. caller = whoever initiated
  # the exchange (inbound for voice/sms in; staff for sms out).
  def channel_id(caller, callee) when is_binary(caller) and is_binary(callee),
    do: "tel_#{caller}_#{callee}"

  def tool_call_status_pending, do: "pending"
  def tool_call_status_ok, do: "ok"
  def tool_call_status_error, do: "error"

  def tool_call_statuses,
    do: [tool_call_status_pending(), tool_call_status_ok(), tool_call_status_error()]

  # tool_call type — where in the call lifecycle the tool fires.
  #   before    — pre-conversation lookups; no openai frame, openai_call_id nil.
  #   midflight — model-driven during the call; openai_call_id matches the frame.
  #   after     — post-call actions; server-initiated, openai_call_id nil.
  def tool_call_type_before, do: "before"
  def tool_call_type_midflight, do: "midflight"
  def tool_call_type_after, do: "after"

  def tool_call_types,
    do: [tool_call_type_before(), tool_call_type_midflight(), tool_call_type_after()]

  # operator-spoken phrase that hard-stops a scammer test call. shared by
  # the scammer system prompt (the LLM is told to break character on it)
  # and `FraudDetector.Heuristics` (belt-and-braces — if the LLM ignores
  # the instruction, the heuristic still trips and forces a hangup).
  def stop_test_phrase, do: "STOP TEST"
end
