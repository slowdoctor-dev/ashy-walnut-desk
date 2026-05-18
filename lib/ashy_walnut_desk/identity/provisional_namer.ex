defmodule AshyWalnutDesk.Identity.ProvisionalNamer do
  @moduledoc """
  Deterministic display-name generator for provisional Identity rows
  created by an inbound webhook (ADR-024 Q5 decision).

  The framework's default formats US E.164 phone numbers as
  `"Inbound +1 555 *** 1234"` (country code + area code + masked
  middle + last 4). Generic phone numbers and non-phone identifiers
  fall back to a masked first-3/last-3 shape.

  Deployers in a private repo override this by replacing the
  module via `config :ashy_walnut_desk, :provisional_namer, MyApp.Namer`
  and re-using the `name/1` shape.

  See `specs/phase-3/architecture.md §6.4`.
  """

  @doc """
  Generate a display name for a provisional Identity row given the
  raw identifier (phone number, JID, etc.).
  """
  @spec name(String.t()) :: String.t()
  def name(identifier) when is_binary(identifier) do
    trimmed = String.trim(identifier)
    "Inbound " <> mask(trimmed)
  end

  def name(_), do: "Inbound unknown sender"

  # US E.164 with 10-digit national number after the +1.
  defp mask("+1" <> rest) when byte_size(rest) >= 10 do
    digits = String.replace(rest, ~r/\D/, "")

    if byte_size(digits) >= 10 do
      area = String.slice(digits, 0, 3)
      last = String.slice(digits, -4, 4)
      "+1 #{area} *** #{last}"
    else
      fallback(rest)
    end
  end

  # Generic E.164 (any other country code).
  defp mask("+" <> rest) do
    digits = String.replace(rest, ~r/\D/, "")

    cond do
      byte_size(digits) >= 7 ->
        cc_split = pick_cc_split(digits)
        cc = String.slice(digits, 0, cc_split)
        last = String.slice(digits, -4, 4)
        "+#{cc} *** #{last}"

      byte_size(digits) > 0 ->
        fallback("+" <> digits)

      true ->
        "unknown sender"
    end
  end

  # Non-phone (JID, Line ID, KakaoTalk handle, etc.) — first 3 / last 3.
  defp mask(other), do: fallback(other)

  defp fallback(s) when is_binary(s) do
    if byte_size(s) <= 6 do
      s
    else
      first = String.slice(s, 0, 3)
      last = String.slice(s, -3, 3)
      "#{first}***#{last}"
    end
  end

  # Generic CC split: assume 1-3 leading digits are the country code.
  # For numbers > 11 digits assume 3-digit CC; for 9-11 digits 2-digit;
  # else 1-digit.
  defp pick_cc_split(digits) do
    case byte_size(digits) do
      n when n > 11 -> 3
      n when n >= 9 -> 2
      _ -> 1
    end
  end
end
