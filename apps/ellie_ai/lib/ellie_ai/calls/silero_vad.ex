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

  @doc "run one inference. samples = 256 floats in [-1,1] (for 8khz); state = f32 {2,1,128}."
  def infer(samples, state) when is_list(samples) do
    model = :persistent_term.get(@persist_key)

    input = Nx.tensor([samples], type: :f32)
    sr = Nx.tensor(8000, type: :s64)

    {output, new_state} = Ortex.run(model, {input, state, sr})

    prob = output |> Nx.to_flat_list() |> hd()
    {prob, new_state}
  end

  defp full_path do
    @model_path_override || Path.join(:code.priv_dir(:ellie_ai), @model_relpath)
  end
end
