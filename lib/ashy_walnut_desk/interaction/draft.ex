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
    end

    update :edit_draft do
      accept([
        :body,
        :compensation_body,
        :status,
        :approved_at,
        :approved_by_id,
        :ai_prompt,
        :ai_model,
        :ai_response,
        :ai_validator_output
      ])
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

    policy action(:edit_draft) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
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
      public?(true)
    end
  end
end
