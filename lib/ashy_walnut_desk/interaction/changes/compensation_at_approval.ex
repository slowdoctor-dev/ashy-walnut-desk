defmodule AshyWalnutDesk.Interaction.Changes.CompensationAtApproval do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.{Action, Compensation}
  alias AshyWalnutDesk.Repo

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      draft_id = changeset.data.id
      draft_id_bin = Ecto.UUID.dump!(draft_id)

      case Repo.query(
             "SELECT id FROM drafts WHERE id = $1 AND status = 'drafting' FOR UPDATE",
             [draft_id_bin]
           ) do
        {:ok, %{num_rows: 1}} ->
          validate_compensation_and_stage(changeset, context)

        {:ok, %{num_rows: 0}} ->
          Changeset.add_error(changeset, field: :status, message: "draft_not_drafting")

        {:error, error} ->
          Changeset.add_error(changeset, field: :status, message: Exception.message(error))
      end
    end)
    |> Changeset.after_transaction(fn _changeset, result -> normalize_result(result) end)
  end

  defp validate_compensation_and_stage(changeset, context) do
    compensation_body =
      Changeset.get_attribute(changeset, :compensation_body) ||
        changeset.data.compensation_body

    if is_nil(compensation_body) or String.trim(compensation_body) == "" do
      Changeset.add_error(changeset,
        field: :compensation_body,
        message: "is required when approving a draft"
      )
    else
      draft_id = changeset.data.id
      draft_id_bin = Ecto.UUID.dump!(draft_id)

      with {:ok, %{rows: [[channel_id]]}} <-
             Repo.query(
               """
               SELECT c.channel_id
               FROM drafts d
               JOIN inboxes i ON i.id = d.inbox_id
               JOIN conversations c ON c.id = i.conversation_id
               WHERE d.id = $1
               """,
               [draft_id_bin]
             ),
           {:ok, action} <- create_action(draft_id, channel_id, context),
           {:ok, _compensation} <- create_compensation(action.id, compensation_body, context) do
        changeset
      else
        {:ok, %{rows: []}} ->
          Changeset.add_error(changeset, field: :inbox_id, message: "could not resolve channel")

        {:error, :action_already_exists} ->
          Changeset.add_error(changeset, field: :status, message: "draft_not_drafting")

        {:error, error} ->
          Changeset.add_error(changeset, field: :status, message: Exception.message(error))
      end
    end
  end

  defp create_action(draft_id, channel_id, context) do
    attrs = %{draft_id: draft_id, channel_id: channel_id, status: :pending}

    opts =
      [
        action: :register_pending,
        authorize?: false,
        context: %{from_draft_approve: true}
      ]
      |> maybe_put(:actor, context.actor)

    case Ash.create(Action, attrs, opts) do
      {:ok, action} ->
        {:ok, action}

      {:error, error} ->
        if String.contains?(error_text(error), "actions_draft_id_index") do
          {:error, :action_already_exists}
        else
          {:error, error}
        end
    end
  end

  defp create_compensation(action_id, body, context) do
    opts =
      [
        action: :register,
        authorize?: false,
        context: %{from_draft_approve: true}
      ]
      |> maybe_put(:actor, context.actor)

    Ash.create(Compensation, %{action_id: action_id, status: :registered, body: body}, opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_result({:error, error}) do
    if String.contains?(error_text(error), "draft_not_drafting") do
      {:error, :draft_not_drafting}
    else
      {:error, error}
    end
  end

  defp normalize_result(other), do: other

  defp error_text(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  end
end
