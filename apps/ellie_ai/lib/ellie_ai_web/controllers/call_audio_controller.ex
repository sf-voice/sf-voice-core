defmodule EllieAiWeb.CallAudioController do
  @moduledoc """
  serves per-call audio. if `audio_s3_key` is set, redirect to a presigned
  s3 url so the browser streams from s3 directly. otherwise fall back to
  /tmp/calls/<id>/full.wav (dev boxes without s3 configured).
  """

  use EllieAiWeb, :controller

  alias EllieAi.Calls

  @presign_expires_seconds 60 * 5
  # 15-min token matches how long staff typically keep a call detail page open.
  @token_max_age 60 * 15

  def show(conn, %{"id" => id, "token" => token}) do
    case Phoenix.Token.verify(EllieAiWeb.Endpoint, "call audio", token,
           max_age: @token_max_age
         ) do
      {:ok, ^id} -> serve(conn, id)
      _ -> send_resp(conn, :unauthorized, "")
    end
  end

  # missing token entirely → 401, don't leak whether the call exists.
  def show(conn, _params), do: send_resp(conn, :unauthorized, "")

  defp serve(conn, id) do
    case Calls.get(id) do
      nil ->
        send_resp(conn, :not_found, "")

      %{audio_s3_key: key} when is_binary(key) and key != "" ->
        redirect_to_presigned(conn, key, id)

      _call ->
        serve_local(conn, id)
    end
  end

  defp redirect_to_presigned(conn, key, call_id) do
    case System.get_env("S3_BUCKET_NAME") do
      nil ->
        # bucket env missing in dev — fall back to the local wav.
        serve_local(conn, call_id)

      bucket ->
        config = ExAws.Config.new(:s3)

        case ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: @presign_expires_seconds) do
          {:ok, url} -> redirect(conn, external: url)
          {:error, _} -> send_resp(conn, :bad_gateway, "could not sign audio url")
        end
    end
  end

  defp serve_local(conn, call_id) do
    base = Application.get_env(:ellie_ai, :audio_dir, "/tmp/calls")
    path = Path.join([base, call_id, "full.wav"])

    if File.exists?(path) do
      conn
      |> put_resp_content_type("audio/wav")
      |> send_file(:ok, path)
    else
      send_resp(conn, :not_found, "")
    end
  end
end
