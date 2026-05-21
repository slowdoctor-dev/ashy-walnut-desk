defmodule AshyWalnutDesk.Safety.ValidatorCompositeTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Safety.ValidatorResult
  alias AshyWalnutDesk.Safety.Validators.Composite

  defmodule PassingDeploymentValidator do
    @behaviour AshyWalnutDesk.Safety.Validator
    @behaviour AshyWalnutDesk.Safety.DeploymentValidator

    @impl true
    def version, do: "dep-1"

    @impl true
    def check(_text, _opts) do
      %ValidatorResult{
        passed?: true,
        violations: [],
        baseline_version: "ignored",
        deployment_version: version()
      }
    end
  end

  defmodule BlockingDeploymentValidator do
    @behaviour AshyWalnutDesk.Safety.Validator
    @behaviour AshyWalnutDesk.Safety.DeploymentValidator

    @impl true
    def version, do: "dep-2"

    @impl true
    def check(_text, _opts) do
      %ValidatorResult{
        passed?: false,
        violations: [
          %{
            code: :deployment_rule,
            severity: :error,
            span: nil,
            locale_key: "validator.violations.deployment_rule"
          }
        ],
        baseline_version: "ignored",
        deployment_version: version()
      }
    end
  end

  test "composite defaults deployment validators to [] and keeps baseline result" do
    result = Composite.check("safe text")

    assert is_boolean(result.passed?)
    assert is_binary(result.baseline_version)
    assert result.deployment_version == nil
  end

  test "composite deterministically appends deployment violations and versions" do
    result =
      Composite.check("safe text",
        deployment_validators: [PassingDeploymentValidator, BlockingDeploymentValidator]
      )

    assert result.passed? == false
    assert :deployment_rule in Enum.map(result.violations, & &1.code)
    assert result.deployment_version == "dep-1,dep-2"
    assert is_binary(result.baseline_version)
  end
end
