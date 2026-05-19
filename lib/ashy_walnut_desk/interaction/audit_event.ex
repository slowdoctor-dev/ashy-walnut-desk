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

    create :create do
      accept([
        :chain_topic,
        :event_type,
        :subject_kind,
        :subject_id,
        :payload,
        :prev_hash,
        :hash,
        :actor_id
      ])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  field_policies do
    field_policy :payload do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    field_policy :* do
      authorize_if(always())
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

    # Sec-fix R1: mark the payload sensitive so Ash's default
    # inspect/2 output and any future paper-trail extension on
    # AuditEvent redacts it. The allowlist on
    # `AuditChain.@payload_allowlist` keeps the structure clean, but
    # the *values* are UUIDs of sensitive records (identity_id,
    # action_id, etc.) — usable for enumeration if leaked. Admin
    # `:read` policy is still the primary gate; this is
    # defense-in-depth for logs / inspect output.
    attribute :payload, :map do
      allow_nil?(false)
      sensitive?(true)
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
