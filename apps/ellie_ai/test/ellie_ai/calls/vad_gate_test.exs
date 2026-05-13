defmodule EllieAi.Calls.VadGateTest do
  use ExUnit.Case, async: false

  alias EllieAi.Calls.{CallRegistry, VadGate}

  # uses the real silero model loaded at app boot. silence-only audio
  # should never flip the gate into :speech, so we can verify the
  # hysteresis state machine (and the model + ulaw + buffering pipeline)
  # without staging a fake "user said hello" sample.

  setup do
    # `start_link` links the gate to the test process — it dies when the
    # test exits, so no cleanup needed.
    ccid = "test-vad-#{System.unique_integer([:positive])}"
    {:ok, _pid} = VadGate.start_link(%{ccid: ccid})
    %{ccid: ccid}
  end

  describe "feed/2" do
    test "silence input never triggers a speech_start signal", %{ccid: ccid} do
      # 1 second of μ-law silence (0xFF). plenty of windows for the model
      # to reach steady state. if hysteresis or the model is wrong, we'd
      # see an upward flicker through the 0.5 threshold.
      silence = String.duplicate(<<0xFF>>, 8000)

      # subscribe to messages CallServer would receive. since CallServer
      # isn't running in this test, VadGate.feed → CallServer.speech_*
      # are no-ops at the registry layer (whereis returns nil). the test
      # passes by *not* crashing and by leaving the gate in :silence.
      VadGate.feed(ccid, silence)

      # wait for all buffered windows to be processed.
      :sys.get_state(CallRegistry.whereis_vad_gate(ccid))
      |> tap(fn state ->
        assert state.hysteresis.vad_state == :silence
        assert state.hysteresis.silence_count == 0
      end)
    end

    test "buffers samples that don't fill a full window", %{ccid: ccid} do
      # 100 bytes < 256-sample window. should accumulate in the buffer
      # without running inference.
      partial = String.duplicate(<<0xFF>>, 100)
      VadGate.feed(ccid, partial)

      state = :sys.get_state(CallRegistry.whereis_vad_gate(ccid))
      assert length(state.sample_buffer) == 100
      assert state.hysteresis.vad_state == :silence
    end

    test "drains multiple windows from one chunk", %{ccid: ccid} do
      # 600 bytes = 600 samples = 2 full windows (512) + 88-sample tail.
      bytes = String.duplicate(<<0xFF>>, 600)
      VadGate.feed(ccid, bytes)

      state = :sys.get_state(CallRegistry.whereis_vad_gate(ccid))
      assert length(state.sample_buffer) == 88
      assert state.hysteresis.vad_state == :silence
    end
  end
end
