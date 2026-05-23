# ellie's dev seed. idempotent — safe to run twice.
#
# creates the seasons group + a small fleet of org locations for the
# multi-tenant demo. only the canonical org (`seasons-sf`) is wired to
# a real telnyx number — read from a single `PHONE_NUMBER` env var since
# you can't realistically own multiple numbers for a demo. the other
# locations exist as switcher fodder; assign them numbers via
# /settings → Phone & integrations as you provision more.
#
# the `telnyx_phone_number` column is uniquely constrained, so even if
# you wanted to share one number across orgs it wouldn't insert — kept
# the design here intentionally one-number-one-org.
#
# run: `mise run setup` (full bootstrap) or `mix run priv/repo/seeds.exs`
# inside `apps/ellie_ai`.

alias EllieAi.{Groups, Orgs, Prompts, Settings}

{:ok, group} =
  Groups.upsert_by_slug("seasons", %{
    name: "The Seasons"
  })

# single shared env var. legacy `TELNYX_PHONE_NUMBER` still honored so
# existing .env files don't need renaming.
phone_number =
  System.get_env("PHONE_NUMBER") || System.get_env("TELNYX_PHONE_NUMBER")

# canonical list of orgs. `phone` only set on the primary — the others
# get a `nil` and surface as "No number yet" in /admin/organizations.
orgs = [
  %{
    slug: "seasons-sf",
    name: "The Seasons — San Francisco",
    location: "san francisco, ca",
    time_zone: "America/Los_Angeles",
    phone: phone_number
  },
  %{
    slug: "seasons-la",
    name: "The Seasons — Los Angeles",
    location: "los angeles, ca",
    time_zone: "America/Los_Angeles",
    phone: nil
  },
  %{
    slug: "seasons-ny",
    name: "The Seasons — New York",
    location: "new york, ny",
    time_zone: "America/New_York",
    phone: nil
  }
]

resto_base_url =
  case System.get_env("RESTO_BASE_URL") do
    url when is_binary(url) and url != "" -> url
    _ -> "http://localhost:4000"
  end

# minimal prompt template applied to every org if it has none yet. EEx
# placeholders pick up the org's name/location at call time. operators
# iterate on this via the staff UI without a redeploy.
prompt_body = """
you are ellie, the host taking calls for {{ org.name }}.
greet the caller warmly and briefly. for v0 of this system you are doing
an "echo" demo: repeat back the gist of whatever the caller says, then
ask if there's anything else.

PACE: speak unhurried. callers often need a moment to think; pause
after questions, repeat numbers back slowly, and never rush a
confirmation. it's better to take an extra beat than to talk over
someone or miss a digit.

caller info: {{ customer_intro }}
caller's phone (from telnyx): {{ customer.phone_number }}

phone confirmation: before booking, modifying, or cancelling anything,
confirm the number above is the right one to put on their reservation.
if it isn't (e.g. they're calling from a different phone today), ask
them to read out the number they want and use that instead.

when the caller seems done, thank them and invite them to hang up
whenever they're ready ("feel free to hang up when you're done — i'll
stay on the line"). do NOT try to end the call yourself; let the
caller hang up.

customer flow:
  1. the server auto-fetches the caller's record before this prompt runs.
     `{{ customer_intro }}` above tells you who's on the line — use it.
  2. if the line above says "first-time caller", ASK the caller for
     their name, then call upsert_customer with phone + first_name
     (+ last_name, email, notes if known). this fills in the record.
  3. only AFTER the caller has a name on file can you call
     create_reservation / modify_reservation / cancel_reservation.
     those tools are gated on a named customer; first-timers can't
     book until upsert_customer runs.

restaurant context (read-only):
  • name: {{ org.name }}
  • location: {{ org.location }}
"""

# upsert each org, then bootstrap its per-org rows (runtime settings +
# a default prompt). bootstrap helpers are idempotent so they won't
# clobber operator edits on a second run.
seeded =
  Enum.map(orgs, fn attrs ->
    {:ok, org} =
      Orgs.upsert_by_slug(attrs.slug, %{
        group_id: group.id,
        name: attrs.name,
        location: attrs.location,
        time_zone: attrs.time_zone,
        resto_base_url: resto_base_url,
        resto_org_slug: attrs.slug,
        telnyx_phone_number: attrs.phone
      })

    Settings.bootstrap(org.id, "vad_silence_ms", 700,
      value_type: "int",
      description:
        "milliseconds of detected silence before VadGate declares end-of-turn. " <>
          "lower = snappier, higher = lets callers pause mid-sentence. range 200-3000."
    )

    Settings.bootstrap(org.id, "vad_mode", "silero",
      value_type: "string",
      description: "turn detection: 'silero' (local, default) or 'openai' (server_vad fallback)."
    )

    case Prompts.active(org.id) do
      nil ->
        {:ok, _} =
          Prompts.save_new_version(org.id, %{
            "name" => "v0 echo demo",
            "body" => prompt_body
          })

      _existing ->
        :ok
    end

    {org, attrs.phone}
  end)

IO.puts("\nseeded ellie group=#{group.slug}")

Enum.each(seeded, fn {org, phone} ->
  IO.puts("  • #{String.pad_trailing(org.slug, 16)} → #{phone || "(no number)"}")
end)
