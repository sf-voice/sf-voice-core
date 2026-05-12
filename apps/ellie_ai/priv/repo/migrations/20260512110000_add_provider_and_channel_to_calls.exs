defmodule EllieAi.Repo.Migrations.AddProviderAndChannelToCalls do
  use Ecto.Migration

  def up do
    alter table(:calls) do
      # our own grouping key (`tel_<caller>_<callee>`). ties voice + sms
      # for the same number pair onto one timeline.
      add :channel_id, :string
      # which telephony vendor; future-proofs a switch.
      add :provider, :string, default: "telnyx"
    end

    execute """
    UPDATE calls
    SET channel_id = 'tel_' || COALESCE(from_phone, 'unknown') || '_' || COALESCE(to_phone, 'unknown'),
        provider = 'telnyx'
    WHERE channel_id IS NULL
    """

    # `call_control_id` was leaky vendor-specific naming; `provider_id` is the
    # generic durable id regardless of vendor (still telnyx's ccid today).
    rename table(:calls), :call_control_id, to: :provider_id

    create index(:calls, [:channel_id])

    alter table(:transcript_turns) do
      # voice | sms — direction is derived from (role, medium, call.channel_id).
      add :medium, :string, default: "voice"
    end

    execute "UPDATE transcript_turns SET medium = 'voice' WHERE medium IS NULL"
  end

  def down do
    alter table(:transcript_turns) do
      remove :medium
    end

    drop index(:calls, [:channel_id])

    rename table(:calls), :provider_id, to: :call_control_id

    alter table(:calls) do
      remove :channel_id
      remove :provider
    end
  end
end
