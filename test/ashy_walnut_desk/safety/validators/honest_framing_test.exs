defmodule AshyWalnutDesk.Safety.Validators.HonestFramingTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Safety.HonestFraming
  alias AshyWalnutDesk.Safety.Validators.HonestFraming, as: HonestFramingValidator

  test "shares banned terms from single source" do
    assert HonestFraming.banned_terms() == ["unsend", "undo send", "recall message", "take back"]
  end

  test "returns no violations for safe text" do
    assert HonestFramingValidator.check("Thanks for your message.") == []
  end

  test "returns honest_framing violation for banned runtime phrase" do
    [violation] = HonestFramingValidator.check("I can unsend that for you")

    assert violation.code == :honest_framing
    assert violation.severity == :error
    assert violation.span == nil
    assert violation.locale_key == "validator.violations.honest_framing"
  end
end
