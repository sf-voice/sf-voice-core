defmodule EllieAi.Phones do
  @moduledoc """
  phone-string normalization for telnyx boundaries.

  three layers of recovery so a SIP-mangled caller-id like
  `"+1442070817673@152.189.4.248:5060"` round-trips into a clean E.164:

    1. `clean/1` strips SIP `@host:port` suffixes.
    2. `to_e164/1` tries strict international parsing first.
    3. if the input is `+1XXX...` and too long to be US, drop the `1`
       and retry (the Google Voice / SIP-relay mangling case).
    4. if still no match, walk a list of fallback regions
       (`@candidate_regions`) and take the first valid parse.

  the candidate-region list is biased toward the markets ellie actually
  sees today. extend it as new markets light up.
  """

  # used by to_e164/1 when the input has no `+` and strict parsing fails.
  # order matters — first valid parse wins, so put your dominant market first.
  @candidate_regions ~w(US GB AU IN CA)

  @doc """
  drop the SIP `@host:port` (or `;params`) suffix from a phone-like
  string. nil and unparseable input pass through unchanged.
  """
  @spec clean(String.t() | nil) :: String.t() | nil
  def clean(nil), do: nil

  def clean(raw) when is_binary(raw) do
    raw
    |> String.split("@", parts: 2)
    |> hd()
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
  end

  def clean(other), do: other

  @doc """
  best-effort E.164 from a phone string that may be SIP-suffixed,
  prefix-mangled by a SIP relay, or in national format.

  returns `{:ok, "+EEEE..."}` or `{:error, reason}`.
  """
  @spec to_e164(String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def to_e164(nil), do: {:error, :nil_input}

  def to_e164(raw) when is_binary(raw) do
    phone = clean(raw)

    with {:error, _} <- parse_strict(phone),
         {:error, _} <- recover_from_mangled_plus1(phone),
         {:error, _} <- try_with_regions(phone, @candidate_regions) do
      {:error, "unparseable phone: #{inspect(raw)}"}
    end
  end

  def to_e164(_), do: {:error, :unparseable_input}

  # strict: input must carry its own country code via `+`. ExPhoneNumber
  # parses without a default region.
  defp parse_strict(phone) do
    with {:ok, parsed} <- ExPhoneNumber.parse(phone, nil),
         true <- ExPhoneNumber.is_valid_number?(parsed) do
      {:ok, ExPhoneNumber.format(parsed, :e164)}
    else
      _ -> {:error, :strict_invalid}
    end
  end

  # Layer 1: SIP relays (notably Google Voice) sometimes prepend a
  # spurious `+1` to an international caller's number. detect by length —
  # if there are more digits after `+1` than fit a US national number,
  # try parsing without the `1`.
  defp recover_from_mangled_plus1("+1" <> rest) when byte_size(rest) > 10,
    do: parse_strict("+" <> rest)

  defp recover_from_mangled_plus1(_), do: {:error, :not_applicable}

  # Layer 2: walk a list of fallback regions. only triggers when the
  # input lacks `+` (national format from a known market).
  defp try_with_regions(_phone, []), do: {:error, :unparseable}

  defp try_with_regions(phone, [region | rest]) do
    with {:ok, parsed} <- ExPhoneNumber.parse(phone, region),
         true <- ExPhoneNumber.is_valid_number?(parsed) do
      {:ok, ExPhoneNumber.format(parsed, :e164)}
    else
      _ -> try_with_regions(phone, rest)
    end
  end
end
