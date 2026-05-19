defmodule AshyWalnutDesk.Identity.Note do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Identity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Accounts.Checks.AdminOrOperator
  alias AshyWalnutDesk.Identity.Changes.SoftDelete

  postgres do
    table("notes")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:identity, on_delete: :restrict)
    end

    custom_indexes do
      index([:identity_id, :deleted_at])
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

    create :record_note do
      accept([:body, :identity_id])
      change(relate_actor(:recorded_by))
    end

    update :edit_note do
      accept([:body])
      require_atomic?(false)
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

    policy action(:record_note) do
      authorize_if(AdminOrOperator)
    end

    policy action(:edit_note) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(expr(recorded_by_id == ^actor(:id)))
    end

    policy action(:archive) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(expr(recorded_by_id == ^actor(:id)))
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  field_policies do
    field_policy :body do
      authorize_if(AdminOrOperator)
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :body, :string do
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
    belongs_to :identity, AshyWalnutDesk.Identity.Identity do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :recorded_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(false)
      # FK set exclusively via `change(relate_actor(:recorded_by))` on
      # :record_note. Marked non-writable so a future caller adding
      # `:recorded_by_id` to an accept list cannot bypass the
      # actor-relation pattern.
      attribute_writable?(false)
      public?(true)
    end
  end
end
