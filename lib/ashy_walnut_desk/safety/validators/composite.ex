defmodule AshyWalnutDesk.Safety.Validators.Composite do
  @moduledoc false

  @behaviour AshyWalnutDesk.Safety.Validator

  alias AshyWalnutDesk.Safety.DeploymentValidator
  alias AshyWalnutDesk.Safety.ValidatorResult
  alias AshyWalnutDesk.Safety.Validators.Baseline

  @deployment_validators Application.compile_env(
                           :ashy_walnut_desk,
                           :deployment_validators,
                           []
                         )

  @impl true
  def check(text, opts \\ []) when is_binary(text) do
    deployment_validators = Keyword.get(opts, :deployment_validators, @deployment_validators)
    baseline = Baseline.check(text, opts)

    {deployment_violations, deployment_versions} =
      Enum.reduce(deployment_validators, {[], []}, fn validator, {violations, versions} ->
        result = validator.check(text, opts)
        next_versions = append_version(versions, validator, result)
        {violations ++ result.violations, next_versions}
      end)

    violations = baseline.violations ++ deployment_violations

    %ValidatorResult{
      passed?: Enum.all?(violations, &(&1.severity != :error)),
      violations: violations,
      baseline_version: baseline.baseline_version,
      deployment_version: join_versions(deployment_versions)
    }
  end

  defp append_version(versions, validator, result) do
    case result.deployment_version || version_for(validator) do
      nil -> versions
      version -> versions ++ [version]
    end
  end

  defp version_for(validator) do
    if function_exported?(validator, :version, 0) and
         DeploymentValidator in (validator.module_info(:attributes)[:behaviour] || []) do
      validator.version()
    else
      nil
    end
  end

  defp join_versions([]), do: nil
  defp join_versions(versions), do: Enum.join(versions, ",")
end
