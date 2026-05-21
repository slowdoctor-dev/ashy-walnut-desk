defmodule AshyWalnutDesk.Safety.ValidatorI18nTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Safety.Validators.Baseline

  test "baseline exposes gettext-backed keys for each violation" do
    text = "I guarantee this will work and costs $5, plus you can unsend it."

    result = Baseline.check(text)

    assert Enum.all?(result.violations, fn violation ->
             translated = Baseline.violation_message(violation.locale_key)
             is_binary(translated) and translated != ""
           end)
  end
end
