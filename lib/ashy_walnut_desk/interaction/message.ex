defmodule AshyWalnutDesk.Interaction.Message do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  postgres do
    table("messages")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:conversation, on_delete: :restrict)
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
    defaults([:read])
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
      authorize_if(actor_attribute_equals(:role, :viewer))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :direction, :atom do
      allow_nil?(false)
      constraints(one_of: [:inbound, :outbound])
      public?(true)
    end

    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :sent_at, :utc_datetime_usec do
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
    belongs_to :conversation, AshyWalnutDesk.Interaction.Conversation do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :approved_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(true)
      public?(true)
    end
  end
end
