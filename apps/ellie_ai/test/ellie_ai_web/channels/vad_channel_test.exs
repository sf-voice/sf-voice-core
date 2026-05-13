defmodule EllieAiWeb.VadChannelTest do
  use ExUnit.Case, async: true

  import Phoenix.ChannelTest

  alias EllieAiWeb.{Endpoint, VadSocket}

  @endpoint Endpoint

  # matches config/test.exs.
  @test_token "test-internal-api-token"

  # 256 little-endian f32 zero samples = 1024 bytes = one valid window.
  @silence_window :binary.copy(<<0.0::little-float-32>>, 256)

  describe "connect/3 — auth" do
    test "rejects connections without a token" do
      assert :error = connect(VadSocket, %{})
    end

    test "rejects connections with a wrong token" do
      assert :error = connect(VadSocket, %{"token" => "nope"})
    end

    test "accepts connections with the shared bearer" do
      assert {:ok, _socket} = connect(VadSocket, %{"token" => @test_token})
    end
  end

  describe "join/3" do
    setup do
      {:ok, socket} = connect(VadSocket, %{"token" => @test_token})
      %{socket: socket}
    end

    test "joins vad:stream:<id> and seeds hysteresis from silence_ms param", %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, "vad:stream:abc", %{"silence_ms" => 320})
      assert channel.assigns.hysteresis.min_silence_windows == 10
      assert channel.assigns.hysteresis.vad_state == :silence
    end

    test "rejects unknown topic", %{socket: socket} do
      assert {:error, %{reason: "unknown topic"}} =
               subscribe_and_join(socket, "vad:not-a-stream", %{})
    end
  end

  describe "handle_in audio" do
    setup do
      {:ok, socket} = connect(VadSocket, %{"token" => @test_token})
      {:ok, _reply, channel} = subscribe_and_join(socket, "vad:stream:test", %{})
      %{channel: channel}
    end

    test "wrong window size replies with a bad_window_size error", %{channel: channel} do
      bad = :binary.copy(<<0.0::little-float-32>>, 100)
      ref = push(channel, "audio", {:binary, bad})

      assert_reply ref, :error, %{
        reason: "bad_window_size",
        expected_bytes: 1024,
        got_bytes: 400
      }
    end

    test "non-binary audio is rejected", %{channel: channel} do
      ref = push(channel, "audio", [0.0, 0.0, 0.0])
      assert_reply ref, :error, %{reason: "audio must be a binary push"}
    end

    test "valid silence window pushes a frame reply with a numeric prob", %{channel: channel} do
      push(channel, "audio", {:binary, @silence_window})
      assert_push "frame", %{prob: prob}
      assert is_float(prob)
    end

    test "silence-only stream never emits speech_start", %{channel: channel} do
      # push enough silence windows that any flicker through 0.5 would surface.
      for _ <- 1..50 do
        push(channel, "audio", {:binary, @silence_window})
      end

      # drain "frame" replies and assert none carry a transition event.
      Enum.each(1..50, fn _ ->
        assert_push "frame", payload
        refute Map.has_key?(payload, :event)
      end)
    end
  end
end
