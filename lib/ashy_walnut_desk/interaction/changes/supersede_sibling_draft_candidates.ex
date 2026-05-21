defmodule AshyWalnutDesk.Interaction.Changes.SupersedeSiblingDraftCandidates do
  @moduledoc false

  use Ash.Resource.Change

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.Draft

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      draft = changeset.data
      actor = actor_from_changeset(changeset)

      siblings =
        Draft
        |> Ash.Query.for_read(:read, %{}, authorize?: false)
        |> Ash.Query.filter(
          expr(inbox_id == ^draft.inbox_id and status == :drafting and id != ^draft.id)
        )
        |> Ash.Query.sort(created_at: :asc)
        |> Ash.read!(authorize?: false)

      superseded_ids =
        Enum.map(siblings, fn sibling ->
          {:ok, superseded} =
            Ash.update(
              sibling,
              %{},
              action: :supersede,
              actor: actor,
              authorize?: false
            )

          superseded.id
        end)

      Ash.Changeset.set_context(changeset, %{
        superseded_sibling_draft_ids: superseded_ids
      })
    end)
  end

  defp actor_from_changeset(changeset) do
    case Map.get(changeset.relationships, :approved_by) do
      {[first | _], _opts} when is_map(first) and not is_nil(first.id) ->
        first

      [first | _] when is_map(first) and not is_nil(first.id) ->
        first

      _ ->
        nil
    end
  end
end
