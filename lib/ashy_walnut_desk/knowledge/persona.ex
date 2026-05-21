defmodule AshyWalnutDesk.Knowledge.Persona do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Knowledge,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Accounts.Checks.AdminOrOperator
  alias AshyWalnutDesk.Identity.Changes.SoftDelete

  @allowed_models Application.compile_env(
                    :ashy_walnut_desk,
                    :ai_model_allowlist,
                    []
                  )

  postgres do
    table("personas")
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

    read(:read_with_archived)

    create :create do
      accept([
        :name,
        :slug,
        :system_prompt,
        :disclosure_text,
        :guardrail_notes,
        :model_override,
        :status
      ])

      validate(string_length(:system_prompt, min: 64, max: 8_000))
      validate(string_length(:disclosure_text, min: 1, max: 500))
      validate(string_length(:guardrail_notes, max: 4_000))
      change(&validate_model_override/2)
    end

    update :update do
      accept([
        :name,
        :system_prompt,
        :disclosure_text,
        :guardrail_notes,
        :model_override,
        :status
      ])

      require_atomic?(false)
      validate(string_length(:system_prompt, min: 64, max: 8_000))
      validate(string_length(:disclosure_text, min: 1, max: 500))
      validate(string_length(:guardrail_notes, max: 4_000))
      change(&validate_model_override/2)
    end

    update :archive do
      accept([])
      require_atomic?(false)
      change(SoftDelete)
      change(set_attribute(:status, :archived))
    end

    update :recover do
      accept([])
      require_atomic?(false)
      change(set_attribute(:deleted_at, nil))
      change(set_attribute(:status, :active))
    end
  end

  policies do
    policy action(:read) do
      authorize_if(AdminOrOperator)
    end

    policy action(:read_with_archived) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action_type([:create, :update]) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:archive) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  field_policies do
    field_policy [:system_prompt, :disclosure_text, :guardrail_notes, :model_override] do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      constraints(max_length: 200)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      constraints(max_length: 120, match: ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
      public?(true)
      writable?(true)
    end

    attribute :system_prompt, :string do
      allow_nil?(false)
      sensitive?(true)
      constraints(max_length: 8_000)
      public?(true)
    end

    attribute :disclosure_text, :string do
      allow_nil?(false)
      sensitive?(true)
      constraints(max_length: 500)
      public?(true)
    end

    attribute :guardrail_notes, :string do
      allow_nil?(true)
      sensitive?(true)
      constraints(max_length: 4_000)
      public?(true)
    end

    attribute :model_override, :string do
      allow_nil?(true)
      sensitive?(true)
      constraints(max_length: 200)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:active)
      constraints(one_of: [:active, :archived])
      public?(true)
    end

    attribute :deleted_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  defp validate_model_override(changeset, _context) do
    case Ash.Changeset.get_attribute(changeset, :model_override) do
      nil ->
        changeset

      model when model in @allowed_models ->
        changeset

      model ->
        Ash.Changeset.add_error(
          changeset,
          field: :model_override,
          message: "must be in %{list}",
          vars: [list: Enum.join(@allowed_models, ", ")],
          value: model
        )
    end
  end
end
