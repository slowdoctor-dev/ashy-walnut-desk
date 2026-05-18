defmodule AshyWalnutDesk.Interaction.Action do
  @moduledoc false

  alias Ash.Changeset

  alias AshyWalnutDesk.Interaction.Changes.{
    ChainLink,
    CountdownGuard,
    EnqueueOutboundSend,
    RecordOutbound
  }

  alias AshyWalnutDesk.Interaction.Checks.{FromActionWorker, FromDraftApprove}
  alias AshyWalnutDesk.Interaction.Validations.StatusTransition

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  postgres do
    table("actions")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:draft, on_delete: :restrict)
      reference(:channel, on_delete: :restrict)
    end

    custom_indexes do
      index([:draft_id], unique: true)
    end
  end

  actions do
    default_accept([])
    defaults([:read])

    create :register_pending do
      accept([:draft_id, :channel_id])
      change(set_attribute(:status, :pending))

      # Story 3.4 / ADR-023: stamp a deterministic idempotency key
      # at register-time. Used by Oban worker as the Twilio
      # Idempotency-Key header so retries don't double-send.
      change(fn changeset, _ctx ->
        Changeset.force_change_attribute(
          changeset,
          :outbound_idempotency_key,
          "action-" <> Ash.UUID.generate()
        )
      end)
    end

    update :execute do
      accept([])
      require_atomic?(false)
      # A1: prevent replay-execute. Without this guard, calling :execute
      # twice would re-invoke the adapter, double-billing or duplicating
      # the outbound message.
      validate({StatusTransition, from: [:pending]})
      change(CountdownGuard)
      change(EnqueueOutboundSend)
      change({ChainLink, event_type: :action_scheduled})
    end

    # Internal: invoked by `Jobs.OutboundSend` only (gated by
    # `FromActionWorker` policy check). Persists the adapter response,
    # transitions the Action to `:executed`, writes the outbound
    # `Message` row + marks Inbox `:executed`, and emits the
    # `:action_executed` audit event with `outcome: :ok`.
    update :complete_outbound do
      accept([:adapter_response])
      require_atomic?(false)
      validate({StatusTransition, from: [:scheduled]})
      change(set_attribute(:status, :executed))
      change(set_attribute(:executed_at, &DateTime.utc_now/0))
      change(RecordOutbound)
      change({ChainLink, event_type: :action_executed})
    end

    # Internal: invoked by `Jobs.OutboundSend` on permanent adapter
    # failure or exhausted retry budget. Stamps the error string,
    # transitions to `:failed`, and emits the `:action_executed`
    # audit event with `outcome: :failed`.
    update :fail_outbound do
      accept([:error])
      require_atomic?(false)
      validate({StatusTransition, from: [:scheduled, :pending]})
      change(set_attribute(:status, :failed))
      change({ChainLink, event_type: :action_executed})
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    policy action(:execute) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    # S2: internal-only. Must originate from `Draft.approve`'s
    # `CompensationAtApproval` change. An operator calling this
    # directly would create an Action without the matching Compensation
    # row — breaking the four-stage chain (ADR-016).
    policy action(:register_pending) do
      authorize_if(FromDraftApprove)
    end

    # Worker-only transitions. Operator cannot mark an Action
    # `:executed` or `:failed` directly — only `Jobs.OutboundSend`
    # sets the `from_action_worker` context flag.
    policy action(:complete_outbound) do
      authorize_if(FromActionWorker)
    end

    policy action(:fail_outbound) do
      authorize_if(FromActionWorker)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:pending, :scheduled, :executed, :failed, :rolled_back])
      public?(true)
    end

    attribute :adapter_response, :map do
      allow_nil?(true)
      public?(true)
    end

    attribute :executed_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :error, :string do
      allow_nil?(true)
      public?(true)
    end

    # Story 3.4: deterministic per-Action idempotency key used by
    # `Adapters.Twilio.send_outbound/2` as the `Idempotency-Key`
    # header so Oban retries don't double-send (ADR-023).
    # Derived from `action_id` (one-to-one) at register_pending time
    # so retries see the same value.
    attribute :outbound_idempotency_key, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :draft, AshyWalnutDesk.Interaction.Draft do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :channel, AshyWalnutDesk.Interaction.Channel do
      allow_nil?(false)
      public?(true)
    end
  end
end
