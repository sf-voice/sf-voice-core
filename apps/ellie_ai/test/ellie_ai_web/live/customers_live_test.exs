defmodule EllieAiWeb.CustomersLiveTest do
  use EllieAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EllieAi.{Groups, Orgs}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EllieAi.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, group} = Groups.create(%{slug: "g-#{System.unique_integer([:positive])}", name: "G"})

    {:ok, org} =
      Orgs.create(%{
        group_id: group.id,
        slug: "o-#{System.unique_integer([:positive])}",
        name: "Test Org",
        resto_base_url: "http://localhost:4000",
        resto_org_slug: "o"
      })

    %{org: org}
  end

  describe "/" do
    test "renders heading + empty states", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Live calls"
      assert html =~ "Customers"
      # empty states are visible — no calls, no customers seeded.
      assert html =~ "No active calls"
    end
  end

  describe "/settings" do
    test "renders settings page heading", %{conn: conn, org: org} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
      assert html =~ org.name
    end

    test "renders both sub-forms with the editable fields", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      # Identity tab fields.
      assert html =~ "Identity"
      assert html =~ "Time zone"
      # Integrations tab fields (rendered in the dom even when the
      # tab isn't visually active — tabs are css, not server-side gating).
      assert html =~ "Telnyx phone number"
      assert html =~ "Resto base URL"
      assert html =~ "Resto org slug"
      # both forms have stable ids so tests can address them unambiguously.
      assert html =~ ~s(id="org-identity-form")
      assert html =~ ~s(id="org-integrations-form")
    end

    test "saving the identity form persists name + location", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> form("#org-identity-form", %{
          "org" => %{"name" => "New Name", "location" => "Mission, SF"}
        })
        |> render_submit()

      assert html =~ "Org saved"

      reloaded = Orgs.get(org.id)
      assert reloaded.name == "New Name"
      assert reloaded.location == "Mission, SF"
    end

    test "saving the integrations form normalizes the telnyx number to E.164",
         %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> form("#org-integrations-form", %{
          "org" => %{
            "telnyx_phone_number" => "8774980043",
            "resto_base_url" => org.resto_base_url,
            "resto_org_slug" => org.resto_org_slug
          }
        })
        |> render_submit()

      assert html =~ "Org saved"

      # national-only input gets canonicalized to E.164 by the schema.
      assert Orgs.get(org.id).telnyx_phone_number == "+18774980043"
    end

    test "rejects a malformed telnyx number inline (regression for the +8774980043 bug)",
         %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> form("#org-integrations-form", %{
          "org" => %{
            # missing US country code — ExPhoneNumber rejects.
            "telnyx_phone_number" => "+8774980043",
            "resto_base_url" => org.resto_base_url,
            "resto_org_slug" => org.resto_org_slug
          }
        })
        |> render_submit()

      assert html =~ "Couldn&#39;t save org" or html =~ "Couldn't save org"
      # inline field-level error renders under the input. the apostrophe in
      # "couldn't" comes back HTML-escaped, so match the stem `parse` (or
      # the alt error path "plausible") which survives escaping intact.
      assert html =~ "parse" or html =~ "plausible phone number"

      # DB was not mutated.
      assert Orgs.get(org.id).telnyx_phone_number == org.telnyx_phone_number
    end
  end
end
