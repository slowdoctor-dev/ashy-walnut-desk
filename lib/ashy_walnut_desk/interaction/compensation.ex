defmodule AshyWalnutDesk.Interaction.Compensation do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  alias Ash.Changeset

  alias AshyWalnutDesk.Interaction.Changes.{
    ChainLink,
    CompensationCountdownGuard,
    EnqueueCompensationSend
  }

  alias AshyWalnutDesk.Interaction.Checks.{FromActionWorker, FromDraftApprove}
  alias AshyWalnutDesk.Interaction.Validations.StatusTransition

  postgres do
    table("compensations")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:action, on_delete: :restrict)
    end

    custom_indexes do
      index([:action_id], unique: true)
    end
  end

  actions do
    default_accept([])
    defaults([:read])

    create :register do
      accept([:action_id, :body, :triggered_at])
      change(set_attribute(:status, :registered))
    end

    # Story 3.6 step 1 of 2: operator clicked "Trigger compensation".
    # Stamps `trigger_initiated_at` so `CompensationCountdownGuard`
    # can enforce the 5-second rule on the follow-up `:trigger` call.
    # No adapter call here; just a status flip + timestamp.
    update :initiate_trigger do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:registered]})
      change(set_attribute(:status, :triggering))
      change(set_attribute(:trigger_initiated_at, &DateTime.utc_now/0))

      # Stamp the idempotency key now so Oban retries (on the
      # follow-up `:trigger` call's enqueue) reuse the same value.
      change(fn changeset, _ctx ->
        Changeset.force_change_attribute(
          changeset,
          :outbound_idempotency_key,
          "compensation-" <> Ash.UUID.generate()
        )
      end)
    end

    # Story 3.6 step 2 of 2: after the 5-second countdown UI elapses,
    # validate the server-side timestamp and enqueue the Oban worker.
    # Same chain shape as `Action.:execute` per ADR-023.
    update :trigger do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:triggering]})
      change(CompensationCountdownGuard)
      change(set_attribute(:status, :scheduled))
      change(EnqueueCompensationSend)
      change({ChainLink, event_type: :compensation_scheduled})
    end

    # Internal: invoked by `Jobs.OutboundSend` on adapter success.
    update :complete_send do
      accept([:adapter_response])
      require_atomic?(false)
      validate({StatusTransition, from: [:scheduled]})
      change(set_attribute(:status, :triggered))
      change(set_attribute(:triggered_at, &DateTime.utc_now/0))
      change({ChainLink, event_type: :compensation_executed})
    end

    # Internal: invoked by `Jobs.OutboundSend` on permanent / exhausted
    # adapter failure.
    update :fail_send do
      accept([:error])
      require_atomic?(false)
      validate({StatusTransition, from: [:scheduled, :triggering]})
      change(set_attribute(:status, :failed))
      change({ChainLink, event_type: :compensation_executed})
    end

    # Story 3.fix: stuck-state recovery. If an operator clicks
    # "Trigger compensation" (→ :triggering) and then the LV crashes
    # / the operator closes the tab before the 5-second countdown
    # elapses, the Compensation is stuck in :triggering with no
    # path back. An admin can reset it to :registered to retry.
    # No chain event written — the original
    # `:compensation_registered` event still stands.
    update :reset_trigger do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:triggering]})
      change(set_attribute(:status, :registered))
      change(set_attribute(:trigger_initiated_at, nil))
      change(set_attribute(:outbound_idempotency_key, nil))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    # R2-3: internal-only. Must originate from `Draft.approve`'s
    # `CompensationAtApproval` change. An operator calling this
    # directly would forge a compensation row without a real approval
    # behind it.
    policy action(:register) do
      authorize_if(FromDraftApprove)
    end

    policy action(:initiate_trigger) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:trigger) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:complete_send) do
      authorize_if(FromActionWorker)
    end

    policy action(:fail_send) do
      authorize_if(FromActionWorker)
    end

    # Recovery action is admin-only. Operators may have legitimate
    # need to retry but the route requires an explicit admin
    # judgment — re-arming a send is a sensitive operation.
    policy action(:reset_trigger) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:registered, :triggering, :scheduled, :triggered, :completed, :failed])
      public?(true)
    end

    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    # Story 3.6: server-stamped at `:initiate_trigger` time. The
    # `CompensationCountdownGuard` rejects `:trigger` calls that
    # arrive less than 5 seconds later (ADR-013).
    attribute :trigger_initiated_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :triggered_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :adapter_response, :map do
      allow_nil?(true)
      public?(true)
    end

    attribute :error, :string do
      allow_nil?(true)
      public?(true)
    end

    # Story 3.6: same shape as `Action.outbound_idempotency_key`.
    # Stamped at `:initiate_trigger` so a retry of `:trigger` (e.g.
    # Oban worker re-runs after worker crash) carries the same key.
    attribute :outbound_idempotency_key, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :action, AshyWalnutDesk.Interaction.Action do
      allow_nil?(false)
      public?(true)
    end
  end
end
