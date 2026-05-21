defmodule AshyWalnutDesk.Safety.Validators.BaselineTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Safety.Validators.Baseline

  test "returns passing result for safe text" do
    result = Baseline.check("Thank you for your message. Please contact us with any questions.")

    assert result.passed?
    assert result.violations == []
    assert is_binary(result.baseline_version)
    assert result.deployment_version == nil
  end

  test "flags each baseline violation code with error severity" do
    long_suffix = String.duplicate("x", 2_010)

    result =
      Baseline.check(
        "I guarantee you have this issue. It will cost $25. You can unsend later. " <> long_suffix
      )

    codes = MapSet.new(Enum.map(result.violations, & &1.code))

    assert :guarantee_claim in codes
    assert :diagnostic_claim in codes
    assert :pricing_assertion in codes
    assert :honest_framing in codes
    assert :length_exceeded in codes

    assert Enum.all?(result.violations, &(&1.severity == :error))
    assert result.passed? == false
  end

  test "version is deterministic" do
    assert Baseline.version() == Baseline.version()
  end
end
