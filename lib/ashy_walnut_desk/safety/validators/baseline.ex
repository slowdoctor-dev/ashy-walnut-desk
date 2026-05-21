defmodule AshyWalnutDesk.Safety.Validators.Baseline do
  @moduledoc false

  @behaviour AshyWalnutDesk.Safety.Validator
  use Gettext, backend: AshyWalnutDeskWeb.Gettext

  alias AshyWalnutDesk.Safety.ValidatorResult
  alias AshyWalnutDesk.Safety.Validators.HonestFraming

  @max_length 2_000
  @prohibited_phrases []

  @guarantee_patterns [
    ~r/\bi guarantee\b/i,
    ~r/\bwe guarantee\b/i,
    ~r/\bwe promise\b/i,
    ~r/\bguaranteed\b/i
  ]

  @diagnostic_patterns [
    ~r/\bdiagnosis\b/i,
    ~r/\bi diagnose\b/i,
    ~r/\byou (have|are experiencing)\b/i,
    ~r/\bdefinitely (have|are)\b/i
  ]

  @pricing_patterns [
    ~r/\$\s?\d+(?:[\.,]\d{2})?/,
    ~r/\busd\s?\d+(?:[\.,]\d{2})?/i,
    ~r/\b\d+(?:[\.,]\d{2})?\s?(dollars|usd)\b/i
  ]

  @rule_signature %{
    max_length: @max_length,
    prohibited_phrases: @prohibited_phrases,
    guarantee_patterns: Enum.map(@guarantee_patterns, &Regex.source/1),
    diagnostic_patterns: Enum.map(@diagnostic_patterns, &Regex.source/1),
    pricing_patterns: Enum.map(@pricing_patterns, &Regex.source/1),
    honest_framing_terms: AshyWalnutDesk.Safety.HonestFraming.banned_terms()
  }

  @version @rule_signature
           |> :erlang.term_to_binary()
           |> then(&:crypto.hash(:sha256, &1))
           |> Base.encode16(case: :lower)

  @spec version() :: String.t()
  def version, do: @version

  @impl true
  def check(text, _opts \\ []) when is_binary(text) do
    violations =
      []
      |> maybe_add(:guarantee_claim, text, has_match?(text, @guarantee_patterns))
      |> maybe_add(:diagnostic_claim, text, has_match?(text, @diagnostic_patterns))
      |> maybe_add(:pricing_assertion, text, has_match?(text, @pricing_patterns))
      |> maybe_add(:prohibited_phrase, text, has_prohibited_phrase?(text))
      |> maybe_add(:length_exceeded, text, String.length(text) > @max_length)
      |> Kernel.++(HonestFraming.check(text))

    %ValidatorResult{
      passed?: Enum.all?(violations, &(&1.severity != :error)),
      violations: violations,
      baseline_version: version(),
      deployment_version: nil
    }
  end

  @spec violation_message(String.t()) :: String.t()
  def violation_message("validator.violations.guarantee_claim"),
    do: dgettext("default", "validator.violations.guarantee_claim")

  def violation_message("validator.violations.diagnostic_claim"),
    do: dgettext("default", "validator.violations.diagnostic_claim")

  def violation_message("validator.violations.pricing_assertion"),
    do: dgettext("default", "validator.violations.pricing_assertion")

  def violation_message("validator.violations.prohibited_phrase"),
    do: dgettext("default", "validator.violations.prohibited_phrase")

  def violation_message("validator.violations.honest_framing"),
    do: dgettext("default", "validator.violations.honest_framing")

  def violation_message("validator.violations.length_exceeded"),
    do: dgettext("default", "validator.violations.length_exceeded")

  def violation_message(locale_key) when is_binary(locale_key), do: locale_key

  defp has_match?(text, patterns), do: Enum.any?(patterns, &Regex.match?(&1, text))

  defp has_prohibited_phrase?(text) do
    downcased = String.downcase(text)
    Enum.any?(@prohibited_phrases, &String.contains?(downcased, String.downcase(&1)))
  end

  defp maybe_add(violations, _code, _text, false), do: violations

  defp maybe_add(violations, code, _text, true) do
    locale_key = "validator.violations.#{code}"

    _ = violation_message(locale_key)

    violations ++
      [
        %{
          code: code,
          severity: :error,
          span: nil,
          locale_key: locale_key
        }
      ]
  end
end
