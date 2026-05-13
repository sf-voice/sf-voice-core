defmodule EllieAi.Vad.HysteresisTest do
  use ExUnit.Case, async: true

  alias EllieAi.Vad.Hysteresis

  describe "new/1" do
    test "default 700ms silence at 32ms windows = ~21 windows" do
      h = Hysteresis.new()
      assert h.window_ms == 32
      assert h.min_silence_windows == div(700, 32)
      assert h.vad_state == :silence
      assert h.silence_count == 0
    end

    test "custom silence_ms" do
      h = Hysteresis.new(silence_ms: 200)
      assert h.min_silence_windows == div(200, 32)
    end
  end

  describe "feed/2 — silence baseline" do
    test "sub-threshold probs in :silence stay silent and emit nothing" do
      h = Hysteresis.new()
      assert {h2, []} = Hysteresis.feed(h, 0.1)
      assert h2.vad_state == :silence

      assert {h3, []} = Hysteresis.feed(h2, 0.49)
      assert h3.vad_state == :silence
    end
  end

  describe "feed/2 — silence → speech transition" do
    test "prob ≥ 0.5 in :silence emits :speech_start and flips state" do
      h = Hysteresis.new()
      assert {h2, [:speech_start]} = Hysteresis.feed(h, 0.5)
      assert h2.vad_state == :speech

      # subsequent speech-prob frames stay in :speech with no new events
      assert {h3, []} = Hysteresis.feed(h2, 0.9)
      assert h3.vad_state == :speech
    end
  end

  describe "feed/2 — speech → silence hangover" do
    test "single quiet window mid-speech does not emit :speech_end" do
      h = Hysteresis.new(silence_ms: 200)
      # min_silence_windows = 200/32 = 6
      {h, _} = Hysteresis.feed(h, 0.9)
      assert h.vad_state == :speech

      # 5 quiet windows — under the threshold of 6
      h =
        Enum.reduce(1..5, h, fn _, acc ->
          {acc2, events} = Hysteresis.feed(acc, 0.1)
          assert events == []
          acc2
        end)

      assert h.vad_state == :speech
      assert h.silence_count == 5
    end

    test ":speech_end fires once the silence count reaches the threshold" do
      h = Hysteresis.new(silence_ms: 200)
      {h, _} = Hysteresis.feed(h, 0.9)

      # consume 5 quiet windows, then the 6th should fire :speech_end
      h =
        Enum.reduce(1..5, h, fn _, acc ->
          {acc2, _} = Hysteresis.feed(acc, 0.1)
          acc2
        end)

      assert {h_final, [:speech_end]} = Hysteresis.feed(h, 0.1)
      assert h_final.vad_state == :silence
      assert h_final.silence_count == 0
    end

    test "a window above 0.35 mid-hangover resets the silence count" do
      h = Hysteresis.new(silence_ms: 200)
      {h, _} = Hysteresis.feed(h, 0.9)

      # 3 quiet windows
      h =
        Enum.reduce(1..3, h, fn _, acc ->
          {acc2, _} = Hysteresis.feed(acc, 0.1)
          acc2
        end)

      assert h.silence_count == 3

      # one borderline window above silence_threshold — resets the counter
      {h, []} = Hysteresis.feed(h, 0.4)
      assert h.vad_state == :speech
      assert h.silence_count == 0
    end
  end
end
