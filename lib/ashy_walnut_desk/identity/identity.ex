defmodule AshyWalnutDesk.Identity.Identity do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Identity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Identity.Changes.HashPrimaryIdentifier
  alias AshyWalnutDesk.Identity.Changes.SoftDelete

  postgres do
    table("identities")
    repo(AshyWalnutDesk.Repo)
  end

  paper_trail do
    change_tracking_mode(:changes_only)
    store_action_name?(true)
    sensitive_attributes(:redact)
    version_extensions(authorizers: [Ash.Policy.Authorizer])
    mixin(AshyWalnutDesk.Identity.Identity.VersionPolicies)
  end

  actions do
    default_accept([])

    read :read do
      primary?(true)
      filter(expr(is_nil(deleted_at)))
    end

    read :read_with_archived do
    end

    create :register_identity do
      accept([:display_name, :notes_summary])

      argument :primary_identifier, :string do
        allow_nil?(false)
        sensitive?(true)
      end

      change(relate_actor(:created_by))
      change(HashPrimaryIdentifier)
    end

    update :update_profile do
      accept([:display_name, :notes_summary])
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

    policy action(:register_identity) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:update_profile) do
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

    attribute :display_name, :ci_string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :primary_identifier_hash, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :notes_summary, :string do
      allow_nil?(true)
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
    belongs_to :created_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end
  end
end
