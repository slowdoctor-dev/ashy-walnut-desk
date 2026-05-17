defmodule AshyWalnutDesk.Identity.Appointment do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Identity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Identity.Changes.SoftDelete
  alias AshyWalnutDesk.Identity.Validations.OriginatingEventLink

  postgres do
    table("appointments")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:identity, on_delete: :restrict)
      reference(:originating_event, on_delete: :restrict)
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

    create :schedule_appointment do
      accept([
        :scheduled_for,
        :appointment_type,
        :summary,
        :identity_id,
        :originating_event_id
      ])

      change(relate_actor(:recorded_by))
    end

    update :reschedule do
      accept([:scheduled_for])
      require_atomic?(false)
    end

    update :cancel do
      accept([])
      require_atomic?(false)
      change(set_attribute(:status, :cancelled))
    end

    update :complete do
      accept([])
      require_atomic?(false)
      change(set_attribute(:status, :completed))
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

  validations do
    validate(OriginatingEventLink, on: [:create, :update])
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

    policy action(:schedule_appointment) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:reschedule) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:cancel) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end

    policy action(:complete) do
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

    attribute :scheduled_for, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    attribute :appointment_type, :atom do
      allow_nil?(false)
      constraints(one_of: [:initial, :follow_up, :recurring])
      default(:initial)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:scheduled, :cancelled, :completed])
      default(:scheduled)
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
    belongs_to :identity, AshyWalnutDesk.Identity.Identity do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :originating_event, AshyWalnutDesk.Identity.Event do
      allow_nil?(true)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :recorded_by, AshyWalnutDesk.Accounts.User do
      allow_nil?(false)
      # FK set exclusively via `change(relate_actor(:recorded_by))` on
      # :schedule_appointment. Marked non-writable so a future caller
      # adding `:recorded_by_id` to an accept list cannot bypass the
      # actor-relation pattern.
      attribute_writable?(false)
      public?(true)
    end
  end
end
