defmodule AshyWalnutDesk.Interaction.Compensation do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Interaction,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  postgres do
    table("compensations")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:action, on_delete: :restrict)
    end

    custom_indexes do
      index([:action_id], unique: true)
    end
  end

  actions do
    default_accept([])
    defaults([:read])

    create :register do
      accept([:action_id, :status, :body, :triggered_at])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    policy action(:register) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:registered, :triggered, :completed, :failed])
      public?(true)
    end

    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :triggered_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :action, AshyWalnutDesk.Interaction.Action do
      allow_nil?(false)
      public?(true)
    end
  end
end
