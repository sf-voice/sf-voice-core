defmodule EllieAi.Calls.Archivist do
  @moduledoc """
  per-call audio recorder. streams inbound + outbound μ-law to two files
  under `/tmp/calls/<call_id>/`. on terminate: merges to stereo wav,
  uploads to s3 (or leaves on disk if no creds), persists key + duration
  on the calls row. per-upload `upload_id` avoids overwriting on replay.
  """

  use GenServer

  alias EllieAi.Calls
  alias EllieAi.Calls.{CallRegistry, Memory, WavEncoder}

  require Logger

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :transient,
      shutdown: 15_000
    }
  end

  def start_link(%{ccid: ccid} = args) when is_binary(ccid) do
    GenServer.start_link(__MODULE__, args, name: CallRegistry.via_archivist(ccid))
  end

  def feed_inbound(ccid, bytes) when is_binary(ccid) and is_binary(bytes),
    do: CallRegistry.cast_to_archivist(ccid, {:inbound, bytes})

  def feed_outbound(ccid, bytes) when is_binary(ccid) and is_binary(bytes),
    do: CallRegistry.cast_to_archivist(ccid, {:outbound, bytes})

  @impl true
  def init(%{ccid: ccid}) do
    Process.flag(:trap_exit, true)
    Logger.metadata(ccid: ccid)
    Memory.bootstrap_from(ccid)

    case Calls.get_by_ccid(ccid) do
      nil ->
        Logger.warning("archivist: no call row for ccid=#{ccid}, skipping archival")
        :ignore

      call ->
        dir = call_dir(call.id)
        File.mkdir_p!(dir)

        {:ok, inbound} = File.open(Path.join(dir, "inbound.ulaw"), [:write, :binary, :raw])
        {:ok, outbound} = File.open(Path.join(dir, "outbound.ulaw"), [:write, :binary, :raw])

        Logger.info(
          "archivist: started call_id=#{call.id} org_id=#{call.org_id} dir=#{dir}"
        )

        {:ok,
         %{
           ccid: ccid,
           call_id: call.id,
           org_id: call.org_id,
           dir: dir,
           inbound: inbound,
           outbound: outbound,
           inbound_bytes: 0,
           outbound_bytes: 0
         }}
    end
  end

  @impl true
  def handle_cast({:inbound, bytes}, state) do
    :ok = IO.binwrite(state.inbound, bytes)
    {:noreply, %{state | inbound_bytes: state.inbound_bytes + byte_size(bytes)}}
  end

  def handle_cast({:outbound, bytes}, state) do
    :ok = IO.binwrite(state.outbound, bytes)
    {:noreply, %{state | outbound_bytes: state.outbound_bytes + byte_size(bytes)}}
  end

  @impl true
  def terminate(_reason, state) do
    _ = File.close(state.inbound)
    _ = File.close(state.outbound)

    Logger.info(
      "archivist: terminate call_id=#{state.call_id} " <>
        "inbound=#{state.inbound_bytes}b outbound=#{state.outbound_bytes}b"
    )

    case finalize(state) do
      :ok -> Logger.info("archivist: finalized call_id=#{state.call_id}")
      {:error, reason} -> Logger.warning("archivist: finalize failed: #{inspect(reason)}")
    end

    :ok
  end

  defp finalize(%{dir: dir, call_id: call_id, org_id: org_id}) do
    with {:ok, inbound} <- File.read(Path.join(dir, "inbound.ulaw")),
         {:ok, outbound} <- File.read(Path.join(dir, "outbound.ulaw")),
         {:has_audio?, true} <- {:has_audio?, byte_size(inbound) + byte_size(outbound) > 0} do
      {wav_iodata, duration_ms} = WavEncoder.encode_stereo(inbound, outbound)
      wav_path = Path.join(dir, "full.wav")
      :ok = File.write(wav_path, wav_iodata)
      wav_size = File.stat!(wav_path).size

      upload_id = Ecto.UUID.generate()
      key = "orgs/#{org_id}/calls/#{call_id}/#{upload_id}.wav"

      Logger.info(
        "archivist: wav written call_id=#{call_id} bytes=#{wav_size} duration_ms=#{duration_ms} key=#{key}"
      )

      case upload(wav_path, key) do
        :ok ->
          Logger.info("archivist: s3 upload ok key=#{key}")
          persist(call_id, key, duration_ms)

        {:skipped, reason} ->
          Logger.info("archivist: s3 upload skipped — #{reason}; wav at #{wav_path}")
          persist(call_id, nil, duration_ms)

        {:error, reason} ->
          Logger.warning("archivist: s3 upload failed: #{inspect(reason)}; wav at #{wav_path}")
          persist(call_id, nil, duration_ms)
      end
    else
      {:has_audio?, false} ->
        Logger.info("archivist: no audio captured for call_id=#{call_id}, skipping wav")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(call_id, key, duration_ms) do
    Calls.set_audio(call_id, key, duration_ms)
    :ok
  end

  defp upload(path, key) do
    case bucket() do
      nil ->
        {:skipped, "no S3_BUCKET_NAME configured"}

      bucket ->
        case s3_creds() do
          {:ok, _} ->
            started = System.monotonic_time(:millisecond)

            try do
              path
              |> ExAws.S3.Upload.stream_file()
              |> ExAws.S3.upload(bucket, key, content_type: "audio/wav")
              |> ExAws.request()
              |> case do
                {:ok, _} ->
                  Logger.info(
                    "archivist: s3 PUT bucket=#{bucket} key=#{key} " <>
                      "in #{System.monotonic_time(:millisecond) - started}ms"
                  )

                  :ok

                {:error, reason} ->
                  {:error, reason}
              end
            rescue
              e -> {:error, Exception.message(e)}
            end

          :error ->
            {:skipped, "no AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in env"}
        end
    end
  end

  defp bucket, do: System.get_env("S3_BUCKET_NAME")

  defp s3_creds do
    case {System.get_env("AWS_ACCESS_KEY_ID"), System.get_env("AWS_SECRET_ACCESS_KEY")} do
      {k, s} when is_binary(k) and is_binary(s) and k != "" and s != "" -> {:ok, {k, s}}
      _ -> :error
    end
  end

  defp call_dir(call_id) do
    base = Application.get_env(:ellie_ai, :audio_dir, "/tmp/calls")
    Path.join(base, call_id)
  end
end
