defmodule AshyWalnutDesk.Interaction.Changes.CountdownGuard do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.{Channel, Draft, Message}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      if Map.get(changeset.context, :from_draft_approve, false) do
        changeset
      else
        run_countdown_and_execute(changeset)
      end
    end)
    |> Changeset.after_action(fn changeset, action ->
      maybe_record_outbound(changeset, action, context)
    end)
  end

  defp run_countdown_and_execute(changeset) do
    with {:ok, draft} <- load_draft_with_inbox(changeset.data.draft_id),
         :ok <- countdown_ok?(draft),
         {:ok, channel} <- Ash.get(Channel, changeset.data.channel_id, authorize?: false),
         {:ok, adapter} <- resolve_adapter(channel.adapter_module),
         {:ok, payload} <- adapter.send_outbound(draft.body, channel) do
      changeset
      |> Changeset.force_change_attribute(:status, :executed)
      |> Changeset.force_change_attribute(:executed_at, DateTime.utc_now())
      |> Changeset.force_change_attribute(:adapter_response, payload)
      |> Changeset.set_context(%{
        outbound_message: %{
          conversation_id: draft.inbox.conversation_id,
          body: draft.body,
          approved_by_id: draft.approved_by_id
        }
      })
    else
      {:error, :countdown_violation} ->
        Changeset.add_error(changeset, field: :draft_id, message: "countdown_violation")

      {:error, error} ->
        changeset
        |> Changeset.force_change_attribute(:status, :failed)
        |> Changeset.force_change_attribute(:error, error_text(error))
    end
  end

  defp maybe_record_outbound(changeset, action, context) do
    if action.status == :executed do
      %{outbound_message: outbound} = changeset.context

      with {:ok, _message} <-
             Ash.create(
               Message,
               %{
                 conversation_id: outbound.conversation_id,
                 direction: :outbound,
                 body: outbound.body,
                 sent_at: action.executed_at,
                 approved_by_id: outbound.approved_by_id
               },
               action: :record_message,
               authorize?: false,
               context: %{from_action_execute: true}
             ),
           {:ok, draft} <- load_draft_with_inbox(action.draft_id),
           {:ok, _inbox} <-
             Ash.update(
               draft.inbox,
               %{status: :executed},
               action: :update_inbox,
               actor: context.actor
             ) do
        {:ok, action}
      else
        {:error, error} -> {:error, error}
      end
    else
      {:ok, action}
    end
  end

  defp countdown_ok?(draft) do
    cond do
      is_nil(draft.approved_at) ->
        {:error, :countdown_violation}

      DateTime.diff(DateTime.utc_now(), draft.approved_at, :second) < 5 ->
        {:error, :countdown_violation}

      true ->
        :ok
    end
  end

  defp resolve_adapter(module_name) when is_binary(module_name) do
    module = Module.concat([module_name])

    if Code.ensure_loaded?(module) and function_exported?(module, :send_outbound, 2) do
      {:ok, module}
    else
      {:error, "channel misconfigured: adapter has no send_outbound/2"}
    end
  rescue
    ArgumentError ->
      {:error, "channel misconfigured: adapter module not loaded"}
  end

  defp load_draft_with_inbox(draft_id) do
    case Ash.get(Draft, draft_id, authorize?: false) do
      {:ok, draft} ->
        {:ok, Ash.load!(draft, [:inbox], authorize?: false)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp error_text(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  end
end
