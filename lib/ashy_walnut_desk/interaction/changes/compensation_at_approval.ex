defmodule AshyWalnutDesk.Interaction.Changes.CompensationAtApproval do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.{Action, Compensation, ErrorHelpers, Locks}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      case Locks.lock_drafting_draft(changeset.data.id) do
        {:ok, :locked} ->
          validate_compensation_and_stage(changeset, context)

        {:ok, :not_drafting} ->
          Changeset.add_error(changeset, field: :status, message: "draft_not_drafting")

        {:error, error} ->
          Changeset.add_error(changeset, field: :status, message: error_text(error))
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
      with {:ok, channel_id} when not is_atom(channel_id) <-
             Locks.resolve_channel_for_draft(changeset.data.id),
           {:ok, action} <- create_action(changeset.data.id, channel_id, context),
           {:ok, compensation} <- create_compensation(action.id, compensation_body, context) do
        # S4: stash the just-created chain rows so `ChainLink` can
        # write the `:draft_approved` + `:compensation_registered`
        # events without re-querying. Falls back to a fresh DB read
        # if absent — keeps `ChainLink` usable from direct tests /
        # future actions that don't go through this path.
        Changeset.set_context(changeset, %{
          chain_payload: %{action: action, compensation: compensation}
        })
      else
        {:ok, :not_found} ->
          Changeset.add_error(changeset, field: :inbox_id, message: "could not resolve channel")

        {:error, :action_already_exists} ->
          Changeset.add_error(changeset, field: :status, message: "draft_not_drafting")

        {:error, error} ->
          Changeset.add_error(changeset, field: :status, message: error_text(error))
      end
    end
  end

  defp create_action(draft_id, channel_id, context) do
    attrs = %{draft_id: draft_id, channel_id: channel_id}

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

    Ash.create(Compensation, %{action_id: action_id, body: body}, opts)
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

  defp error_text(error), do: ErrorHelpers.error_to_string(error)
end
