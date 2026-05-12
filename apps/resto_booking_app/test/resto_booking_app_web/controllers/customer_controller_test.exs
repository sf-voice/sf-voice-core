defmodule RestoBookingAppWeb.CustomerControllerTest do
  # exercises the customer + contact API surface ellie depends on for its
  # "incoming call → who's this?" lookup waterfall and on-call create flow.
  use RestoBookingAppWeb.ConnCase, async: false

  alias RestoBookingApp.Orgs

  setup do
    {:ok, org} =
      Orgs.upsert_by_slug("test-org", %{
        name: "Test Org",
        location: "Testville",
        time_zone: "America/Los_Angeles"
      })

    %{org: org}
  end

  defp authed(conn) do
    token = Application.fetch_env!(:resto_booking_app, :internal_api_token)
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)
  end

  describe "POST /api/orgs/:org_slug/customers (idempotent on phone)" do
    test "creates a customer + phone contact when phone is unseen", %{conn: conn, org: org} do
      conn =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{org.slug}/customers", %{
          "phone" => "+14155550101",
          "first_name" => "Lois",
          "last_name" => "Tester",
          "email" => "lois@example.com"
        })

      json = json_response(conn, 201)
      assert json["customer"]["first_name"] == "Lois"

      kinds = Enum.map(json["customer"]["contacts"], & &1["kind"]) |> Enum.sort()
      assert kinds == ["email", "phone"]

      assert Enum.find(json["customer"]["contacts"], &(&1["kind"] == "phone"))["value"] ==
               "+14155550101"
    end

    test "returns the same customer for repeat calls (idempotent)", %{conn: conn, org: org} do
      first =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{org.slug}/customers", %{
          "phone" => "+14155550102",
          "first_name" => "Same"
        })
        |> json_response(201)

      second =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{org.slug}/customers", %{
          "phone" => "+14155550102",
          "last_name" => "Different"
        })
        |> json_response(201)

      assert first["customer"]["id"] == second["customer"]["id"]
    end

    test "isolation: same phone in two orgs creates two customers", %{conn: conn, org: org} do
      {:ok, other} =
        Orgs.upsert_by_slug("other-org", %{
          name: "Other",
          location: "Elsewhere",
          time_zone: "America/Los_Angeles"
        })

      a =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{org.slug}/customers", %{
          "phone" => "+14155550104",
          "first_name" => "InOrgA"
        })
        |> json_response(201)

      b =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{other.slug}/customers", %{
          "phone" => "+14155550104",
          "first_name" => "InOrgB"
        })
        |> json_response(201)

      refute a["customer"]["id"] == b["customer"]["id"]
    end

    test "400 when phone is missing", %{conn: conn, org: org} do
      conn = conn |> authed() |> post(~p"/api/orgs/#{org.slug}/customers", %{"first_name" => "Lois"})
      json = json_response(conn, 400)
      assert json["errors"]["detail"] =~ "phone"
    end
  end

  describe "GET /api/orgs/:org_slug/customers/by_phone/:phone" do
    test "returns the customer when the phone is known", %{conn: conn, org: org} do
      _ =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{org.slug}/customers", %{
          "phone" => "+14155550103",
          "first_name" => "Looking"
        })
        |> json_response(201)

      json =
        conn
        |> authed()
        |> get(~p"/api/orgs/#{org.slug}/customers/by_phone/#{"+14155550103"}")
        |> json_response(200)

      assert json["customer"]["first_name"] == "Looking"
    end

    test "404 when the phone is unknown", %{conn: conn, org: org} do
      conn =
        conn |> authed() |> get(~p"/api/orgs/#{org.slug}/customers/by_phone/#{"+14155559999"}")

      assert json_response(conn, 404)
    end
  end
end
