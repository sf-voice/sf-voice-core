defmodule EllieAi.Calls.SileroVad do
  @moduledoc """
  loads silero-vad once per vm into `:persistent_term`. sha256-verified
  at boot — a mismatch raises (deploy-pipeline bug, not recoverable).
  """

  require Logger

  @model_relpath "silero_vad/silero_vad.onnx"
  @model_sha256 "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"

  # override in config/{env}.exs when the release ships the model elsewhere.
  @model_path_override Application.compile_env(:ellie_ai, :silero_model_path, nil)

  @persist_key __MODULE__

  @doc "load + verify the model. call once at app boot. raises on missing file or sha mismatch."
  def load! do
    path = full_path()

    unless File.exists?(path) do
      raise "silero vad model not found at #{path}. run `mix deps.get` and check priv/silero_vad/."
    end

    actual_sha =
      path
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    if actual_sha != @model_sha256 do
      raise """
      silero_vad.onnx sha256 mismatch — refusing to load.
        path:     #{path}
        expected: #{@model_sha256}
        actual:   #{actual_sha}
      a corrupted or substituted model is a deploy-pipeline bug.
      """
    end

    model = Ortex.load(path)
    :persistent_term.put(@persist_key, model)
    Logger.info("silero vad loaded (sha256 verified) from #{path}")
    :ok
  end

  @doc "initial recurrent state — f32 zeros of shape {2, 1, 128}. each VadGate threads its own."
  def initial_state do
    Nx.broadcast(Nx.tensor(0.0, type: :f32), {2, 1, 128})
  end

  @doc """
  run one inference. silero v5 supports two sample rates with strict
  window sizes:

    * 8000  Hz → 256 samples per window (32ms)
    * 16000 Hz → 512 samples per window (32ms)

  passing a sample count that doesn't match the rate produces garbage
  probabilities, not an error — so we guard at the boundary.

  `samples` = floats in [-1,1]; `state` = f32 tensor of shape {2,1,128}.
  the 2-arity form defaults to 8khz for backwards-compat with VadGate's
  existing call sites.
  """
  def infer(samples, state), do: infer(samples, state, 8000)

  def infer(samples, state, sample_rate)
      when is_list(samples) and sample_rate in [8000, 16000] do
    expected = window_size_for(sample_rate)

    if length(samples) != expected do
      raise ArgumentError,
            "silero @ #{sample_rate}Hz needs #{expected} samples per window, " <>
              "got #{length(samples)}"
    end

    model = :persistent_term.get(@persist_key)

    input = Nx.tensor([samples], type: :f32)
    sr = Nx.tensor(sample_rate, type: :s64)

    {output, new_state} = Ortex.run(model, {input, state, sr})

    prob = output |> Nx.to_flat_list() |> hd()
    {prob, new_state}
  end

  @doc "samples-per-window for a given sample rate. raises on unsupported rates."
  def window_size_for(8000), do: 256
  def window_size_for(16000), do: 512

  defp full_path do
    @model_path_override || Path.join(:code.priv_dir(:ellie_ai), @model_relpath)
  end
end
