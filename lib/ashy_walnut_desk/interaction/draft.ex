defmodule AshyWalnutDesk.Interaction.Draft do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Identity.Changes.SoftDelete
  alias AshyWalnutDesk.Interaction.Changes.{ChainLink, CompensationAtApproval}

  postgres do
    table("drafts")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:inbox, on_delete: :restrict)
      reference(:approved_by, on_delete: :restrict)
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

    create :compose_draft do
      accept([
        :inbox_id,
        :body,
        :compensation_body,
        :status,
        :ai_prompt,
        :ai_model,
        :ai_response,
        :ai_validator_output
      ])

      change({ChainLink, event_type: :draft_started})
    end

    update :revise do
      accept([
        :body,
        :compensation_body,
        :status,
        :ai_prompt,
        :ai_model,
        :ai_response,
        :ai_validator_output
      ])
    end

    update :approve do
      accept([:compensation_body])
      require_atomic?(false)
      change(CompensationAtApproval)
      change(set_attribute(:status, :approved))
      change(set_attribute(:approved_at, &DateTime.utc_now/0))
      change(relate_actor(:approved_by))
      change({ChainLink, event_type: :draft_approved})
    end

    # Test-only escape hatch: backdate `approved_at` so countdown tests
    # can simulate the 5-second window having elapsed without sleeping.
    # The `forbid_if always()` policy means production callers cannot
    # invoke this — only test fixtures going through `authorize?: false`
    # can. See the AGENTS.md gotcha about fixture actions.
    update :backdate_approval_for_tests do
      accept([:approved_at])
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
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    policy action(:read_with_archived) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:compose_draft) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:revise) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:approve) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:backdate_approval_for_tests) do
      forbid_if(always())
    end

    policy action(:archive) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :compensation_body, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:drafting, :approved, :superseded, :rejected])
      public?(true)
    end

    attribute :approved_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :ai_prompt, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :ai_model, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :ai_response, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :ai_validator_output, :map do
      allow_nil?(true)
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
    belongs_to :inbox, AshyWalnutDesk.Interaction.Inbox do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :approved_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(true)
      # FK set exclusively via `change(relate_actor(:approved_by))` on
      # :approve. Non-writable so a future caller adding
      # `:approved_by_id` to an accept list cannot stamp the approver
      # field directly (countdown bypass).
      attribute_writable?(false)
      public?(true)
    end
  end
end
