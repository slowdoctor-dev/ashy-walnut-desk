defmodule AshyWalnutDesk.Interaction.Changes.AppendDisclosureFooter do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Knowledge.Persona

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, &append_footer/1)
  end

  defp append_footer(changeset) do
    if Enum.any?(changeset.errors) do
      changeset
    else
      body = Ash.Changeset.get_attribute(changeset, :body) || ""

      with persona_id when is_binary(persona_id) <-
             Ash.Changeset.get_data(changeset, :persona_id),
           {:ok, persona} <- Ash.get(Persona, persona_id, authorize?: false),
           disclosure when is_binary(disclosure) <- String.trim(persona.disclosure_text),
           true <- disclosure != "" do
        Changeset.force_change_attribute(changeset, :body, body <> "\n\n" <> disclosure)
      else
        _ -> changeset
      end
    end
  end
end
