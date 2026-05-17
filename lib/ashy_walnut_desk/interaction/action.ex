defmodule AshyWalnutDesk.Interaction.Action do
  @moduledoc false

  alias AshyWalnutDesk.Interaction.Changes.{ChainLink, CountdownGuard, ExecuteOutbound}
  alias AshyWalnutDesk.Interaction.Checks.FromDraftApprove
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
    end

    update :execute do
      accept([])
      require_atomic?(false)
      # A1: prevent replay-execute. Without this guard, calling :execute
      # twice would re-invoke the adapter, double-billing or duplicating
      # the outbound message.
      validate({StatusTransition, from: [:pending]})
      change(CountdownGuard)
      change(ExecuteOutbound)
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
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:pending, :executed, :failed, :rolled_back])
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
