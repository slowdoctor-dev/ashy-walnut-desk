defmodule AshyWalnutDesk.Interaction.Channel do
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
    table("channels")
    repo(AshyWalnutDesk.Repo)

    custom_indexes do
      index([:slug], unique: true)
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

    create :register_channel do
      accept([:slug, :display_name, :adapter_module, :enabled?])
    end

    update :disable do
      accept([])
      change(set_attribute(:enabled?, false))
    end

    update :enable do
      accept([])
      change(set_attribute(:enabled?, true))
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

    policy action(:register_channel) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:disable) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:enable) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:archive) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :display_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :adapter_module, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :enabled?, :boolean do
      allow_nil?(false)
      default(true)
      public?(true)
    end

    attribute :deleted_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end
end
