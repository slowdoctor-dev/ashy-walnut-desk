defmodule AshyWalnutDesk.Interaction.Changes.StampModelFromPersona do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Knowledge.Persona

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, &stamp/1)
  end

  defp stamp(changeset) do
    if Enum.any?(changeset.errors) do
      changeset
    else
      model =
        case Ash.Changeset.get_attribute(changeset, :persona_id) do
          nil ->
            default_model()

          persona_id ->
            persona_model(persona_id) || default_model()
        end

      Changeset.force_change_attribute(changeset, :ai_model, model)
    end
  end

  defp persona_model(persona_id) do
    case Ash.get(Persona, persona_id, authorize?: false) do
      {:ok, persona} -> persona.model_override
      _ -> nil
    end
  end

  defp default_model do
    Application.get_env(:ashy_walnut_desk, :default_model, "claude-sonnet-4-6")
  end
end
