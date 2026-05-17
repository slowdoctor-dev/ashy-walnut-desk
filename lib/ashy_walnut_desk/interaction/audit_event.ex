defmodule AshyWalnutDesk.Interaction.AuditEvent do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  postgres do
    table("audit_events")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:actor, on_delete: :restrict)
    end
  end

  actions do
    default_accept([])
    defaults([:read])
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :chain_topic, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :event_type, :atom do
      allow_nil?(false)
      public?(true)
    end

    attribute :subject_kind, :atom do
      allow_nil?(false)
      public?(true)
    end

    attribute :subject_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :payload, :map do
      allow_nil?(false)
      public?(true)
    end

    attribute :prev_hash, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :hash, :string do
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :actor, AshyWalnutDesk.Accounts.User do
      allow_nil?(true)
      public?(true)
    end
  end
end
