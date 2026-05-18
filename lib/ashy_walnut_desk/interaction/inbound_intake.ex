defmodule AshyWalnutDesk.Interaction.InboundIntake do
  @moduledoc """
  Orchestrates the inbound webhook → chain rows flow per ADR-024:

  1. Resolve / create Identity by `primary_identifier` hash.
  2. Thread or open `Conversation` on `(identity_id, channel_id)`.
  3. Create internal `Inbox.:record_inbound`.
  4. Create inbound `Message.:record_message` with
     `direction: :inbound`.

  All steps run as the system actor inside a single DB transaction.
  Idempotency / replay protection (the `InboundDelivery` ledger) is
  added by story 3.4 — story 3.3 may double-process a Twilio retry.

  See `specs/phase-3/architecture.md §6.2`.
  """

  alias AshyWalnutDesk.Accounts.SystemActor
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, InboundMessage, Inbox, Message}
  alias AshyWalnutDesk.Repo

  require Ash.Query
  import Ash.Expr

  @ctx %{from_inbound_webhook: true}

  @type intake_result ::
          {:ok,
           %{
             identity: Identity.t(),
             conversation: Conversation.t(),
             inbox: Inbox.t(),
             message: Message.t(),
             provisional?: boolean()
           }}
          | {:error, atom()}

  @spec intake(InboundMessage.t(), Channel.t()) :: intake_result
  def intake(%InboundMessage{} = msg, %Channel{} = channel) do
    actor = SystemActor.ensure!()

    Repo.transaction(fn ->
      with {:ok, %{identity: identity, provisional?: provisional?}} <-
             resolve_identity(msg, actor),
           {:ok, conversation} <- thread_or_open(identity, channel, actor),
           {:ok, inbox} <- record_inbound_inbox(conversation, msg, actor),
           {:ok, message} <- record_inbound_message(conversation, msg, actor) do
        %{
          identity: identity,
          conversation: conversation,
          inbox: inbox,
          message: message,
          provisional?: provisional?
        }
      else
        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when is_atom(reason) ->
        {:error, reason}

      {:error, reason} ->
        require Logger

        Logger.warning(
          "inbound intake failed: " <>
            if(is_exception(reason), do: Exception.message(reason), else: inspect(reason))
        )

        {:error, classify(reason)}
    end
  end

  defp resolve_identity(%InboundMessage{from: nil}, _actor), do: {:error, :missing_from}
  defp resolve_identity(%InboundMessage{from: ""}, _actor), do: {:error, :missing_from}

  defp resolve_identity(%InboundMessage{from: raw}, actor) do
    hash = hash_identifier(raw)

    Identity
    |> Ash.Query.filter(expr(primary_identifier_hash == ^hash and is_nil(deleted_at)))
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [identity]} ->
        {:ok, %{identity: identity, provisional?: identity.provisional?}}

      {:ok, []} ->
        case Ash.create(
               Identity,
               %{primary_identifier: raw},
               action: :register_provisional,
               actor: actor,
               context: @ctx
             ) do
          {:ok, identity} -> {:ok, %{identity: identity, provisional?: true}}
          {:error, _} = e -> e
        end

      {:ok, _multiple} ->
        {:error, :ambiguous_identity_match}

      {:error, _} ->
        {:error, :identity_lookup_failed}
    end
  end

  defp thread_or_open(%Identity{} = identity, %Channel{} = channel, actor) do
    Conversation
    |> Ash.Query.filter(
      expr(identity_id == ^identity.id and channel_id == ^channel.id and is_nil(deleted_at))
    )
    |> Ash.Query.sort(created_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [existing]} ->
        {:ok, existing}

      {:ok, []} ->
        Ash.create(
          Conversation,
          %{
            subject: "Inbound thread",
            identity_id: identity.id,
            channel_id: channel.id
          },
          action: :open_conversation,
          actor: actor,
          context: @ctx,
          authorize?: false
        )

      {:error, _} ->
        {:error, :conversation_lookup_failed}
    end
  end

  defp record_inbound_inbox(%Conversation{} = conversation, %InboundMessage{} = msg, actor) do
    Ash.create(
      Inbox,
      %{
        conversation_id: conversation.id,
        summary: inbox_summary(msg)
      },
      action: :record_inbound,
      actor: actor,
      authorize?: false,
      context: @ctx
    )
  end

  defp record_inbound_message(%Conversation{} = conversation, %InboundMessage{} = msg, actor) do
    Ash.create(
      Message,
      %{
        conversation_id: conversation.id,
        direction: :inbound,
        body: msg.body,
        sent_at: msg.received_at
      },
      action: :record_message,
      actor: actor,
      authorize?: false,
      context: @ctx
    )
  end

  defp inbox_summary(%InboundMessage{body: body}) do
    body
    |> to_string()
    |> String.trim()
    |> String.slice(0, 120)
    |> case do
      "" -> "Inbound message (empty body)"
      s -> s
    end
  end

  defp hash_identifier(raw) do
    salt = Application.fetch_env!(:ashy_walnut_desk, :identifier_hash_salt)
    normalized = raw |> to_string() |> String.trim() |> String.downcase()
    :crypto.hash(:sha256, normalized <> salt) |> Base.encode16(case: :lower)
  end

  defp classify(reason) when is_atom(reason), do: reason
  defp classify(_), do: :intake_failed
end
