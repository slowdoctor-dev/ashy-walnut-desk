defmodule AshyWalnutDesk.Interaction.Changes.ExecuteOutbound do
  @moduledoc """
  After the countdown has been verified, invoke the channel adapter,
  record outcome attributes on the Action, and (on success) write the
  outbound Message row + transition the Inbox via `:mark_executed`.

  Depends on `CountdownGuard` having run first and stashed the loaded
  draft into `changeset.context.draft`.

  Adapter contract: receives `%Message{}` (in-memory struct, not yet
  persisted) and `%Channel{}`. Returns `{:ok, payload_map} | {:error,
  reason}`. The persisted Message is created in `after_action` only on
  adapter success.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.{Channel, Message}

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(&do_send/1)
    |> Changeset.after_action(&record_outbound/2)
  end

  defp do_send(changeset) do
    if Enum.any?(changeset.errors) do
      changeset
    else
      attempt_send(changeset)
    end
  end

  defp attempt_send(changeset) do
    draft = Map.fetch!(changeset.context, :draft)

    with {:ok, channel} <- Ash.get(Channel, changeset.data.channel_id, authorize?: false),
         {:ok, adapter} <- resolve_adapter(channel.adapter_module),
         message = build_outbound_message(draft),
         {:ok, payload} <- adapter.send_outbound(message, channel) do
      changeset
      |> Changeset.force_change_attribute(:status, :executed)
      |> Changeset.force_change_attribute(:executed_at, DateTime.utc_now())
      |> Changeset.force_change_attribute(:adapter_response, payload)
      |> Changeset.set_context(%{outbound_message: message})
    else
      {:error, error} ->
        changeset
        |> Changeset.force_change_attribute(:status, :failed)
        |> Changeset.force_change_attribute(:error, error_text(error))
    end
  end

  defp build_outbound_message(draft) do
    %Message{
      conversation_id: draft.inbox.conversation_id,
      direction: :outbound,
      body: draft.body,
      approved_by_id: draft.approved_by_id
    }
  end

  defp record_outbound(changeset, %{status: :executed} = action) do
    draft = Map.fetch!(changeset.context, :draft)
    outbound = Map.fetch!(changeset.context, :outbound_message)

    with {:ok, _message} <- create_outbound_message(outbound, action.executed_at),
         {:ok, _inbox} <- mark_inbox_executed(draft.inbox) do
      {:ok, action}
    end
  end

  defp record_outbound(_changeset, action), do: {:ok, action}

  defp create_outbound_message(%Message{} = template, sent_at) do
    Ash.create(
      Message,
      %{
        conversation_id: template.conversation_id,
        direction: template.direction,
        body: template.body,
        sent_at: sent_at,
        approved_by_id: template.approved_by_id
      },
      action: :record_message,
      authorize?: false,
      context: %{from_action_execute: true}
    )
  end

  defp mark_inbox_executed(inbox) do
    Ash.update(
      inbox,
      %{},
      action: :mark_executed,
      authorize?: false,
      context: %{from_action_execute: true}
    )
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

  defp error_text(error) do
    if is_exception(error), do: Exception.message(error), else: inspect(error)
  end
end
