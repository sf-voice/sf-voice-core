defmodule RestoBookingAppWeb.ReservationControllerTest do
  use RestoBookingAppWeb.ConnCase, async: false

  alias RestoBookingApp.{Clock, Contacts, Menu, Orgs, Tables}

  setup do
    {:ok, org} =
      Orgs.upsert_by_slug("test-org", %{
        name: "Test Org",
        location: "Testville",
        time_zone: "America/Los_Angeles"
      })

    Enum.each(default_tables(), fn t -> {:ok, _} = Tables.upsert(org.id, t) end)
    Enum.each(default_menu(), fn m -> {:ok, _} = Menu.upsert(org.id, m) end)
    %{org: org}
  end

  defp default_tables do
    [
      %{slug: "T1", seats: 2, shape: "round", x: 0, y: 0, sort_order: 1},
      %{slug: "T2", seats: 2, shape: "round", x: 1, y: 0, sort_order: 2},
      %{slug: "T3", seats: 2, shape: "round", x: 2, y: 0, sort_order: 3},
      %{slug: "T4", seats: 2, shape: "round", x: 3, y: 0, sort_order: 4},
      %{slug: "T5", seats: 4, shape: "square", x: 0, y: 1, sort_order: 5},
      %{slug: "T6", seats: 4, shape: "square", x: 1, y: 1, sort_order: 6},
      %{slug: "T7", seats: 4, shape: "square", x: 2, y: 1, sort_order: 7},
      %{slug: "T8", seats: 4, shape: "square", x: 3, y: 1, sort_order: 8},
      %{slug: "T9", seats: 6, shape: "rect", x: 0, y: 2, sort_order: 9}
    ]
  end

  defp default_menu do
    [
      %{service: "breakfast", name: "Toast", price_cents: 700, dietary: [:vegan], sort_order: 1},
      %{
        service: "lunch",
        name: "Caesar",
        price_cents: 1500,
        dietary: [:vegetarian],
        sort_order: 1
      },
      %{
        service: "dinner",
        name: "Tartare",
        price_cents: 2900,
        dietary: [:gluten_free],
        sort_order: 1
      }
    ]
  end

  defp at(hour, minute \\ 0) do
    today = Clock.today()
    {:ok, time} = Time.new(hour, minute, 0)
    today |> Clock.local_to_utc(time) |> DateTime.to_iso8601()
  end

  defp authed(conn) do
    token = Application.fetch_env!(:resto_booking_app, :internal_api_token)
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp fixture_customer(org, opts \\ []) do
    suffix = Keyword.get(opts, :suffix, :rand.uniform(99_999))
    phone = "+1415555#{:io_lib.format("~4..0B", [rem(suffix, 10_000)]) |> IO.iodata_to_binary()}"

    {:ok, customer} =
      Contacts.find_or_create_for_phone(org.id, phone, %{first_name: "API", last_name: "Tester"})

    customer
  end

  defp valid_body(org, overrides \\ %{}) do
    customer =
      Map.get(overrides, :customer) ||
        Map.get(overrides, "customer") ||
        fixture_customer(org)

    overrides = Map.drop(overrides, [:customer, "customer"])

    Map.merge(
      %{
        "table_id" => "T3",
        "starts_at" => at(11),
        "customer_id" => customer.id,
        "party_size" => 2,
        "special_requests" => "no peanuts"
      },
      overrides
    )
  end

  defp create_one(conn, org, overrides \\ %{}) do
    body = valid_body(org, overrides)
    conn = conn |> authed() |> post(~p"/api/orgs/#{org.slug}/reservations", body)
    json = json_response(conn, 201)
    json["reservation"]
  end

  describe "auth" do
    test "rejects requests without a bearer token", %{conn: conn, org: org} do
      conn = post(conn, ~p"/api/orgs/#{org.slug}/reservations", %{})
      assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
    end

    test "rejects requests with the wrong token", %{conn: conn, org: org} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer not-the-token")
        |> get(~p"/api/orgs/#{org.slug}/customers")

      assert json_response(conn, 401)
    end

    test "404 for unknown org", %{conn: conn} do
      conn = conn |> authed() |> get(~p"/api/orgs/no-such-org/customers")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/orgs/:org_slug/reservations" do
    test "creates and returns a cancel_token", %{conn: conn, org: org} do
      res = create_one(conn, org)
      assert res["table_id"] == "T3"
      assert is_binary(res["customer_id"])
      assert is_binary(res["cancel_token"])
      assert is_binary(res["id"])
    end

    test "embeds the customer payload on the response", %{conn: conn, org: org} do
      res = create_one(conn, org)
      assert is_map(res["customer"])
      assert res["customer"]["id"] == res["customer_id"]
    end

    test "422 on overlap", %{conn: conn, org: org} do
      first = create_one(conn, org)

      conn =
        conn
        |> authed()
        |> post(
          ~p"/api/orgs/#{org.slug}/reservations",
          valid_body(org, %{"customer_id" => first["customer_id"]})
        )

      json = json_response(conn, 422)
      assert json["errors"]["starts_at"] == ["table is already booked for this time slot"]
    end

    test "422 when party_size exceeds table seats", %{conn: conn, org: org} do
      conn =
        conn
        |> authed()
        |> post(~p"/api/orgs/#{org.slug}/reservations", valid_body(org, %{"party_size" => 5}))

      json = json_response(conn, 422)
      assert json["errors"]["party_size"] == ["is more than the table's 2 seats"]
    end

    test "422 when customer_id is missing", %{conn: conn, org: org} do
      body = Map.delete(valid_body(org), "customer_id")
      conn = conn |> authed() |> post(~p"/api/orgs/#{org.slug}/reservations", body)
      json = json_response(conn, 422)
      assert json["errors"]["customer_id"] == ["can't be blank"]
    end
  end

  describe "PATCH /api/orgs/:org_slug/reservations/:id" do
    test "updates with the token", %{conn: conn, org: org} do
      res = create_one(conn, org)

      conn =
        conn
        |> authed()
        |> patch(
          ~p"/api/orgs/#{org.slug}/reservations/#{res["id"]}?token=#{res["cancel_token"]}",
          %{"special_requests" => "no peanuts, no shellfish"}
        )

      assert json_response(conn, 200)["reservation"]["special_requests"] ==
               "no peanuts, no shellfish"
    end
  end

  describe "DELETE /api/orgs/:org_slug/reservations/:id" do
    test "deletes with the token", %{conn: conn, org: org} do
      res = create_one(conn, org)

      conn =
        conn
        |> authed()
        |> delete(
          ~p"/api/orgs/#{org.slug}/reservations/#{res["id"]}?token=#{res["cancel_token"]}"
        )

      assert response(conn, 204)
    end
  end

  describe "static endpoints" do
    test "menu returns the seeded services", %{conn: conn, org: org} do
      json = conn |> authed() |> get(~p"/api/orgs/#{org.slug}/menu") |> json_response(200)
      services = Enum.map(json["services"], & &1["service"]) |> Enum.sort()
      assert services == ["breakfast", "dinner", "lunch"]
    end

    test "tables returns the seeded layout", %{conn: conn, org: org} do
      json = conn |> authed() |> get(~p"/api/orgs/#{org.slug}/tables") |> json_response(200)
      assert json["seat_total"] == 30
      assert length(json["tables"]) == 9
    end

    test "list reservations is empty initially", %{conn: conn, org: org} do
      assert conn |> authed() |> get(~p"/api/orgs/#{org.slug}/reservations") |> json_response(200) ==
               %{"reservations" => []}
    end
  end
end
