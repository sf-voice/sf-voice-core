defmodule RestoBookingAppWeb.ReservationControllerTest do
  use RestoBookingAppWeb.ConnCase, async: false

  defp at(hour, minute \\ 0) do
    today = Date.utc_today()
    {:ok, time} = Time.new(hour, minute, 0)
    {:ok, dt} = DateTime.new(today, time, "Etc/UTC")
    DateTime.to_iso8601(dt)
  end

  defp create_one(conn) do
    body = %{
      "table_id" => "T3",
      "starts_at" => at(11),
      "name" => "API Tester",
      "party_size" => 2,
      "dietary" => "no peanuts"
    }

    conn = post(conn, ~p"/api/reservations", body)
    json = json_response(conn, 201)
    json["reservation"]
  end

  describe "POST /api/reservations" do
    test "creates and returns a cancel_token", %{conn: conn} do
      res = create_one(conn)
      assert res["table_id"] == "T3"
      assert is_binary(res["cancel_token"])
      assert is_binary(res["id"])
    end

    test "422 on overlap", %{conn: conn} do
      _ = create_one(conn)

      conn =
        post(conn, ~p"/api/reservations", %{
          "table_id" => "T3",
          "starts_at" => at(11),
          "name" => "Second",
          "party_size" => 2
        })

      json = json_response(conn, 422)
      assert json["errors"]["starts_at"] == ["table is already booked for this time slot"]
    end

    test "422 when party_size exceeds table seats", %{conn: conn} do
      conn =
        post(conn, ~p"/api/reservations", %{
          # T3 is a 2-top
          "table_id" => "T3",
          "starts_at" => at(11),
          "name" => "Big Group",
          "party_size" => 5
        })

      json = json_response(conn, 422)
      assert json["errors"]["party_size"] == ["is more than the table's 2 seats"]
    end
  end

  describe "PATCH /api/reservations/:id" do
    test "updates with the token", %{conn: conn} do
      res = create_one(conn)

      conn =
        patch(conn, ~p"/api/reservations/#{res["id"]}?token=#{res["cancel_token"]}", %{
          "dietary" => "no peanuts, no shellfish"
        })

      assert json_response(conn, 200)["reservation"]["dietary"] == "no peanuts, no shellfish"
    end

    test "403 with wrong token", %{conn: conn} do
      res = create_one(conn)

      conn =
        patch(conn, ~p"/api/reservations/#{res["id"]}?token=wrong", %{
          "dietary" => "x"
        })

      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/reservations/:id" do
    test "deletes with the token", %{conn: conn} do
      res = create_one(conn)

      conn = delete(conn, ~p"/api/reservations/#{res["id"]}?token=#{res["cancel_token"]}")
      assert response(conn, 204)
    end

    test "403 with wrong token", %{conn: conn} do
      res = create_one(conn)

      conn = delete(conn, ~p"/api/reservations/#{res["id"]}?token=bad")
      assert json_response(conn, 403)
    end

    test "400 with no token", %{conn: conn} do
      res = create_one(conn)

      conn = delete(conn, ~p"/api/reservations/#{res["id"]}")
      assert json_response(conn, 400)
    end
  end

  describe "GET /api/reservations and /api/menu and /api/tables" do
    test "menu returns the three services", %{conn: conn} do
      json = conn |> get(~p"/api/menu") |> json_response(200)
      services = Enum.map(json["services"], & &1["service"]) |> Enum.sort()
      assert services == ["breakfast", "dinner", "lunch"]
    end

    test "tables returns 30 seats", %{conn: conn} do
      json = conn |> get(~p"/api/tables") |> json_response(200)
      assert json["seat_total"] == 30
      assert length(json["tables"]) == 9
    end

    test "list reservations is empty initially", %{conn: conn} do
      assert conn |> get(~p"/api/reservations") |> json_response(200) == %{"reservations" => []}
    end
  end
end
