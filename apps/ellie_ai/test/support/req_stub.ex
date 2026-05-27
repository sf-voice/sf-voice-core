defmodule EllieAi.Test.ReqStub do
  @moduledoc """
  small assertions + responses for socket-free Req tests.
  """

  import ExUnit.Assertions
  import Plug.Conn

  def json(conn, method, path, status, body) do
    conn
    |> assert_request(method, path)
    |> put_status(status)
    |> Req.Test.json(body)
  end

  def text(conn, method, path, status, body) do
    conn
    |> assert_request(method, path)
    |> put_status(status)
    |> Req.Test.text(body)
  end

  def transport_error(conn, reason \\ :econnrefused) do
    Req.Test.transport_error(conn, reason)
  end

  def assert_request(conn, method, path) do
    assert conn.method == method
    assert conn.request_path == path
    conn
  end
end
