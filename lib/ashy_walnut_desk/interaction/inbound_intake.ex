defmodule AshyWalnutDesk.Interaction.InboundIntake do
  @moduledoc """
  Orchestrates the inbound webhook → chain rows flow per ADR-024:

  1. Check `InboundDelivery` ledger for dedupe (story 3.4). If we
     already processed this `(provider, provider_message_id)`,
     return `{:ok, %{outcome: :duplicate}}` without re-processing.
  2. Resolve / create Identity by `primary_identifier` hash.
  3. Thread or open `Conversation` on `(identity_id, channel_id)`.
  4. Create internal `Inbox.:record_inbound`.
  5. Create inbound `Message.:record_message` with `:inbound`.
  6. Record `InboundDelivery` with outcome `:processed`.

  Steps 2-6 run as the system actor inside a single DB transaction.
  Failures record `InboundDelivery` with `:failed_intake` outside
  the rolled-back transaction so admin can triage out-of-band.

  See `specs/phase-3/architecture.md §6.2` and ADR-024 C1.
  """

  alias AshyWalnutDesk.Accounts.SystemActor
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Channel,
    Conversation,
    InboundDelivery,
    InboundMessage,
    Inbox,
    Message
  }

  alias AshyWalnutDesk.Repo

  require Ash.Query
  import Ash.Expr

  @ctx %{from_inbound_webhook: true}

  @type intake_outcome :: :processed | :duplicate | :failed_intake

  @type intake_result ::
          {:ok,
           %{
             optional(:identity) => Identity.t(),
             optional(:conversation) => Conversation.t(),
             optional(:inbox) => Inbox.t(),
             optional(:message) => Message.t(),
             optional(:provisional?) => boolean(),
             outcome: intake_outcome()
           }}
          | {:error, atom()}

  @spec intake(InboundMessage.t(), Channel.t()) :: intake_result
  def intake(%InboundMessage{} = msg, %Channel{} = channel) do
    actor = SystemActor.ensure!()

    case existing_delivery(msg) do
      {:ok, %InboundDelivery{outcome: :processed}} ->
        # Already-processed delivery → 2nd+ retry is a duplicate.
        {:ok, %{outcome: :duplicate}}

      {:ok, %InboundDelivery{outcome: previous_outcome}} ->
        # Previous attempt failed (failed_intake). Don't auto-retry;
        # surface the original outcome so admin can triage.
        {:ok, %{outcome: previous_outcome}}

      :missing ->
        do_intake(msg, channel, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_intake(%InboundMessage{} = msg, %Channel{} = channel, actor) do
    Repo.transaction(fn ->
      # Story 3.fix: claim the `(provider, provider_message_id)` slot
      # FIRST. Two concurrent webhooks for the same MessageSid both
      # passed the optimistic `existing_delivery/1` check (no row in
      # the ledger yet); whichever transaction inserts here first
      # wins, and the loser hits the unique constraint immediately —
      # before doing any wasted chain creation. The loser's
      # transaction rolls back wholesale (no orphan rows), and the
      # caller maps the constraint violation to `:duplicate`.
      with {:ok, _delivery} <- record_delivery(msg, :processed, nil),
           {:ok, %{identity: identity, provisional?: provisional?}} <-
             resolve_identity(msg, actor),
           {:ok, conversation} <- thread_or_open(identity, channel, actor),
           {:ok, inbox} <- record_inbound_inbox(conversation, msg, actor),
           {:ok, message} <- record_inbound_message(conversation, msg, actor) do
        %{
          identity: identity,
          conversation: conversation,
          inbox: inbox,
          message: message,
          provisional?: provisional?,
          outcome: :processed
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        handle_transaction_failure(msg, reason)
    end
  end

  defp handle_transaction_failure(msg, reason) do
    cond do
      duplicate_delivery_violation?(reason) ->
        # Lost the race — another concurrent intake claimed the same
        # MessageSid first. Honest reply: this delivery is a
        # duplicate. No `:failed_intake` ledger write needed; the
        # winner's row already exists with `:processed`.
        {:ok, %{outcome: :duplicate}}

      is_atom(reason) ->
        record_delivery_outside_transaction(msg, reason)
        {:error, reason}

      true ->
        require Logger

        Logger.warning(
          "inbound intake failed: " <>
            if(is_exception(reason), do: Exception.message(reason), else: inspect(reason))
        )

        classified = classify(reason)
        record_delivery_outside_transaction(msg, classified)
        {:error, classified}
    end
  end

  # Recognize an Ash error tree whose root cause is the (provider,
  # provider_message_id) unique-constraint violation. We treat this
  # as a duplicate, not a failure. Other invariant violations still
  # bubble up as `:intake_failed`.
  #
  # The reason value passed to `Repo.rollback/1` varies by Ash
  # version / action shape: sometimes `%Ash.Error.Invalid{}` wrapping
  # `%InvalidAttribute{}`, sometimes the raw `Ash.Changeset` carrying
  # `errors:` directly. Handle both.
  defp duplicate_delivery_violation?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &duplicate_delivery_error?/1)
  end

  defp duplicate_delivery_violation?(%Ash.Changeset{errors: errors}) do
    Enum.any?(errors, &duplicate_delivery_error?/1)
  end

  defp duplicate_delivery_violation?(_), do: false

  defp duplicate_delivery_error?(%Ash.Error.Changes.InvalidAttribute{
         field: field,
         private_vars: vars
       })
       when field in [:provider, :provider_message_id] do
    Keyword.get(vars, :constraint_type) == :unique
  end

  defp duplicate_delivery_error?(_), do: false

  defp unique_primary_identifier_hash_violation?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &primary_identifier_hash_unique_error?/1)
  end

  defp unique_primary_identifier_hash_violation?(%Ash.Changeset{errors: errors}) do
    Enum.any?(errors, &primary_identifier_hash_unique_error?/1)
  end

  defp unique_primary_identifier_hash_violation?(_), do: false

  defp primary_identifier_hash_unique_error?(%Ash.Error.Changes.InvalidAttribute{
         field: :primary_identifier_hash,
         private_vars: vars
       }) do
    Keyword.get(vars, :constraint_type) == :unique
  end

  defp primary_identifier_hash_unique_error?(_), do: false

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
          {:ok, identity} ->
            {:ok, %{identity: identity, provisional?: true}}

          {:error, error} ->
            maybe_load_identity_after_unique_race(error, hash)
        end

      {:ok, _multiple} ->
        {:error, :ambiguous_identity_match}

      {:error, _} ->
        {:error, :identity_lookup_failed}
    end
  end

  defp load_identity_by_hash(hash) do
    Identity
    |> Ash.Query.filter(expr(primary_identifier_hash == ^hash and is_nil(deleted_at)))
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [identity]} -> {:ok, %{identity: identity, provisional?: identity.provisional?}}
      {:ok, _} -> {:error, :identity_lookup_failed}
      {:error, _} -> {:error, :identity_lookup_failed}
    end
  end

  defp maybe_load_identity_after_unique_race(error, hash) do
    case unique_primary_identifier_hash_violation?(error) do
      true -> load_identity_by_hash(hash)
      false -> {:error, error}
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
      %{conversation_id: conversation.id, summary: inbox_summary(msg)},
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

  defp existing_delivery(%InboundMessage{provider: provider, provider_message_id: sid}) do
    InboundDelivery
    |> Ash.Query.filter(provider == ^provider)
    |> Ash.Query.filter(provider_message_id == ^sid)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [delivery]} -> {:ok, delivery}
      {:ok, []} -> :missing
      {:ok, _multiple} -> {:error, :ambiguous_delivery_match}
      {:error, _} -> :missing
    end
  end

  defp record_delivery(
         %InboundMessage{provider: provider, provider_message_id: sid},
         outcome,
         reason
       ) do
    Ash.create(
      InboundDelivery,
      %{
        provider: provider,
        provider_message_id: sid,
        outcome: outcome,
        intake_failure_reason: reason && to_string(reason)
      },
      action: :record_delivery,
      authorize?: false,
      context: @ctx
    )
  end

  # Record a delivery row for an intake that failed inside the
  # transaction (which rolled back). Runs in a fresh transaction so
  # the failure is auditable even after rollback.
  #
  # Story 3.fix: the `{:error, _}` clause previously swallowed
  # silently — an admin debugging "why didn't intake X surface as
  # :failed_intake?" would have no trace. The webhook controller
  # still returns 200 to Twilio regardless (see twilio_controller),
  # so logging here doesn't change the response shape, just adds
  # the observability signal.
  defp record_delivery_outside_transaction(msg, reason) do
    case record_delivery(msg, :failed_intake, reason) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        require Logger

        Logger.error(
          "InboundIntake: could not persist :failed_intake ledger row for " <>
            "(#{msg.provider}, #{msg.provider_message_id}): #{inspect(error)}"
        )

        :ok
    end
  end
end
