defmodule AshyWalnutDesk.Interaction.Inbox do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Accounts.Checks.AdminOrOperator
  alias AshyWalnutDesk.Identity.Changes.SoftDelete
  alias AshyWalnutDesk.Interaction.Changes.ChainLink
  alias AshyWalnutDesk.Interaction.Checks.{FromActionExecute, FromInboundWebhook}
  alias AshyWalnutDesk.Interaction.Validations.StatusTransition

  postgres do
    table("inboxes")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:conversation, on_delete: :restrict)
      reference(:recorded_by, on_delete: :restrict)
    end

    # Perf-fix R1: `InboxLive.Index` filters by `status` and sorts
    # by `created_at desc` on every tab switch. Without a composite,
    # PG sequential-scans on a large inboxes table. The composite
    # also serves the `is_nil(deleted_at)` predicate added by the
    # default `:read` action's soft-delete filter — PG can use the
    # leading two columns and apply the soft-delete predicate as a
    # cheap filter on top.
    custom_indexes do
      index([:status, :created_at])
    end
  end

  paper_trail do
    change_tracking_mode(:changes_only)
    store_action_name?(true)
    sensitive_attributes(:redact)
    version_extensions(authorizers: [Ash.Policy.Authorizer])
    mixin(AshyWalnutDesk.AdminOnlyVersions)
  end

  actions do
    default_accept([])

    read :read do
      primary?(true)
      filter(expr(is_nil(deleted_at)))
    end

    read :read_with_archived do
    end

    create :record_inbox do
      accept([:conversation_id, :summary])
      change(set_attribute(:status, :open))
      change(relate_actor(:recorded_by))
      change({ChainLink, event_type: :inbox_opened})
    end

    # ADR-024: internal inbound entry point. Same shape as
    # `:record_inbox` but gated by `FromInboundWebhook` so it can
    # only fire from `Interaction.InboundIntake` running under the
    # system actor; operators must continue to use `:record_inbox`.
    create :record_inbound do
      accept([:conversation_id, :summary])
      change(set_attribute(:status, :open))
      change(relate_actor(:recorded_by))
      change({ChainLink, event_type: :inbox_opened})
    end

    update :mark_drafting do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:open]})
      change(set_attribute(:status, :drafting))
    end

    update :mark_executed do
      accept([])
      require_atomic?(false)
      # Idempotent: multiple Action.execute calls against the same
      # inbox (multiple drafts → multiple actions per inbox) leave the
      # inbox at :executed. We still reject the :dismissed → :executed
      # transition because dismissal is an explicit operator decision
      # to drop the thread.
      validate({StatusTransition, from: [:open, :drafting, :executed]})
      change(set_attribute(:status, :executed))
    end

    update :dismiss do
      accept([])
      require_atomic?(false)
      validate({StatusTransition, from: [:open, :drafting]})
      change(set_attribute(:status, :dismissed))
    end

    update :edit_summary do
      accept([:summary])
    end

    update :archive do
      accept([])
      require_atomic?(false)
      change(SoftDelete)
    end

    update :recover do
      accept([])
      require_atomic?(false)
      change(set_attribute(:deleted_at, nil))
    end
  end

  policies do
    policy action(:read) do
      authorize_if(AdminOrOperator)
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    policy action(:read_with_archived) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:record_inbox) do
      authorize_if(AdminOrOperator)
    end

    policy action(:record_inbound) do
      authorize_if(FromInboundWebhook)
    end

    policy action(:mark_drafting) do
      authorize_if(AdminOrOperator)
    end

    # Internal-only: must originate from `Action.execute`'s
    # `ExecuteOutbound` change, which sets the context flag. Operators
    # cannot transition an inbox to :executed by hand — that would let
    # them mark "the send happened" without the chain (ADR-016) ever
    # firing.
    policy action(:mark_executed) do
      authorize_if(FromActionExecute)
    end

    policy action(:dismiss) do
      authorize_if(AdminOrOperator)
    end

    policy action(:edit_summary) do
      authorize_if(AdminOrOperator)
    end

    policy action(:archive) do
      authorize_if(AdminOrOperator)
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  field_policies do
    field_policy :summary do
      authorize_if(AdminOrOperator)
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:open, :drafting, :executed, :dismissed])
      public?(true)
    end

    attribute :summary, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :deleted_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :conversation, AshyWalnutDesk.Interaction.Conversation do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :recorded_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(false)
      # FK set exclusively via `change(relate_actor(:recorded_by))` on
      # :record_inbox. Non-writable so a future caller adding
      # `:recorded_by_id` to an accept list cannot bypass actor
      # attribution.
      attribute_writable?(false)
      public?(true)
    end

    has_many :latest_drafting_candidates, AshyWalnutDesk.Interaction.Draft do
      filter(expr(status in [:generating, :drafting]))
      sort(created_at: :desc)
      public?(true)
    end
  end
end
