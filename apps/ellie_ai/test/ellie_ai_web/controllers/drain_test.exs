defmodule EllieAiWeb.DrainTest do
  use EllieAiWeb.ConnCase, async: false

  setup do
    EllieAi.Drain.reset!()
    on_exit(fn -> EllieAi.Drain.reset!() end)
    :ok
  end

  test "drain endpoint requires bearer", %{conn: conn} do
    assert post(conn, "/admin/drain") |> response(:unauthorized)
  end

  test "drain flips the flag and is reflected on /health/active_calls", %{conn: conn} do
    token = Application.get_env(:ellie_ai, :internal_api_token)

    conn1 =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/admin/drain")

    assert json_response(conn1, 200) == %{"draining" => true}

    conn2 = get(build_conn(), "/health/active_calls")
    body = json_response(conn2, 200)
    assert body["draining"] == true
    assert is_integer(body["active_calls"])
  end

  test "health/ shows ok", %{conn: conn} do
    assert get(conn, "/health") |> json_response(200) == %{"ok" => true}
  end
end
