defmodule AshyWalnutDesk.Interaction.Validations.ValidatorPassed do
  @moduledoc false

  use Ash.Resource.Validation

  alias AshyWalnutDesk.Safety.HonestFraming

  @impl true
  def validate(changeset, opts, _context) do
    require_ai? = Keyword.get(opts, :require_ai?, false)
    attrs = changeset.attributes || %{}

    validator_output =
      Map.get(attrs, :ai_validator_output, Map.get(changeset.data, :ai_validator_output))

    body = Map.get(attrs, :body, Map.get(changeset.data, :body, ""))

    case validator_output do
      %{"passed?" => true} ->
        :ok

      %{passed?: true} ->
        :ok

      nil when require_ai? ->
        {:error,
         field: :ai_validator_output, message: "must include passed? true validator output"}

      nil ->
        validate_manual_draft(body)

      _ ->
        {:error,
         field: :ai_validator_output, message: "must indicate passed? true before approval"}
    end
  end

  defp validate_manual_draft(body) when is_binary(body) do
    case HonestFraming.check(body) do
      :ok ->
        :ok

      {:error, term} ->
        {:error,
         field: :body, message: "failed honest framing check at approval", vars: [term: term]}
    end
  end

  defp validate_manual_draft(_body), do: {:error, field: :body, message: "must be present"}
end
