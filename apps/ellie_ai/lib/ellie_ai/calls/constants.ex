defmodule EllieAi.Calls.Constants do
  @moduledoc """
  shared calls constants. canonical list of valid call statuses and
  transcript roles, used by both the schemas (`Call`, `TranscriptTurn`)
  and the surfaces that read or write them (`Calls`, `AudioBridge`,
  the customers liveview).

  schema-level literal defaults (e.g. `field :status, :string,
  default: "ringing"` in `Call`) and pattern matches (e.g. in
  `CoreComponents.label_for/1`) keep their string literals — Elixir
  can't reference a function call in either position. those literals
  are acknowledged matches of the canonical values returned here.
  """

  # call lifecycle, in transition order. `missed` covers calls that
  # reached ellie but couldn't be served (replaces the planned
  # `missed_calls` table per the 2026-05-10 review delta).
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

  # transcript turn roles. `staff` was added with the SMS work — a staff
  # member sending an SMS to the caller from the /calls/:id page lands
  # a transcript_turn with role="staff", medium="sms". the AI never
  # writes staff turns; only the LiveView composer does.
  def role_user, do: "user"
  def role_assistant, do: "assistant"
  def role_staff, do: "staff"
  def roles, do: [role_user(), role_assistant(), role_staff()]

  # transcript turn medium. voice turns come from openai's transcription;
  # sms turns from the telnyx messaging webhook (inbound) or our send
  # action (outbound). direction is derived from `(role, medium, call.channel_id)`,
  # so we don't store it.
  def medium_voice, do: "voice"
  def medium_sms, do: "sms"
  def mediums, do: [medium_voice(), medium_sms()]

  # build the channel_id (our own grouping key) from a caller/callee pair.
  # format is `tel_<caller>_<callee>` — caller is whoever initiated the
  # exchange (inbound caller for voice/sms in; staff for sms out).
  def channel_id(caller, callee) when is_binary(caller) and is_binary(callee),
    do: "tel_#{caller}_#{callee}"

  # tool_call lifecycle. `pending` is inserted at dispatch; `ok` / `error`
  # land when the tool returns or times out. surfaced in the staff UI:
  # pending = pulsing dot, ok = solid teal, error = solid red.
  def tool_call_status_pending, do: "pending"
  def tool_call_status_ok, do: "ok"
  def tool_call_status_error, do: "error"

  def tool_call_statuses,
    do: [tool_call_status_pending(), tool_call_status_ok(), tool_call_status_error()]

  # tool_call type — where in the call lifecycle the tool fires.
  #
  #   before    — pre-conversation lookups triggered by `call.initiated`
  #               (e.g. `lookup_customer` keyed on the caller's phone).
  #               no openai function-call frame; openai_call_id is nil.
  #   midflight — model-driven during the call (lookup_availability,
  #               create_reservation, etc.). openai_call_id is the model's
  #               function-call id, used to match the result frame back.
  #   after     — post-call actions (e.g. message_restaurant_owner).
  #               also server-initiated, openai_call_id nil.
  def tool_call_type_before, do: "before"
  def tool_call_type_midflight, do: "midflight"
  def tool_call_type_after, do: "after"

  def tool_call_types,
    do: [tool_call_type_before(), tool_call_type_midflight(), tool_call_type_after()]
end
