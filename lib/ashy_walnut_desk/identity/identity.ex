defmodule AshyWalnutDesk.Identity.Identity do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Identity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource],
    primary_read_warning?: false

  alias AshyWalnutDesk.Accounts.Checks.AdminOrOperator
  alias AshyWalnutDesk.Identity.Changes.HashPrimaryIdentifier
  alias AshyWalnutDesk.Identity.Changes.SoftDelete
  alias AshyWalnutDesk.Identity.ProvisionalNamer
  alias AshyWalnutDesk.Interaction.Checks.FromInboundWebhook

  postgres do
    table("identities")
    repo(AshyWalnutDesk.Repo)

    custom_indexes do
      index([:primary_identifier_hash], unique: true)
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

    create :register_identity do
      accept([:display_name, :notes_summary])

      argument :primary_identifier, :string do
        allow_nil?(false)
        sensitive?(true)
      end

      change(relate_actor(:created_by))
      change(HashPrimaryIdentifier)
    end

    # ADR-024: internal-only. Called from `Interaction.InboundIntake`
    # when an inbound webhook arrives from an unknown identifier.
    # Actor is the system actor; display name is deterministic via
    # `ProvisionalNamer.name/1`.
    create :register_provisional do
      accept([])

      argument :primary_identifier, :string do
        allow_nil?(false)
        sensitive?(true)
      end

      change(fn changeset, _ctx ->
        case Ash.Changeset.get_argument(changeset, :primary_identifier) do
          nil ->
            changeset

          raw ->
            display = ProvisionalNamer.name(to_string(raw))

            changeset
            |> Ash.Changeset.force_change_attribute(:display_name, display)
            |> Ash.Changeset.force_change_attribute(:provisional?, true)
            |> Ash.Changeset.force_change_attribute(:discovered_via, :inbound_webhook)
        end
      end)

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
      authorize_if(AdminOrOperator)
      authorize_if(actor_attribute_equals(:role, :viewer))
    end

    policy action(:read_with_archived) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:register_identity) do
      authorize_if(AdminOrOperator)
    end

    policy action(:register_provisional) do
      authorize_if(FromInboundWebhook)
    end

    policy action(:update_profile) do
      authorize_if(AdminOrOperator)
    end

    policy action(:archive) do
      authorize_if(AdminOrOperator)
    end

    policy action(:recover) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  # Sec-fix R5: field-level gate on the raw `primary_identifier`.
  # The Identity resource's `:read` policy admits admin / operator /
  # viewer (so they see `display_name`, `notes_summary`, etc.). But
  # the raw E.164 lives behind a stricter check: only admins on
  # authorized reads, plus internal worker paths that bypass policy
  # entirely via `authorize?: false`. A viewer or operator getting
  # an Identity row sees `primary_identifier` as `%Ash.ForbiddenField{}`
  # (or nil-ish, depending on Ash version), never the raw value.
  field_policies do
    field_policy :primary_identifier do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    field_policy :primary_identifier_hash do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    # Other fields: same as the resource-level read policy.
    field_policy :* do
      authorize_if(always())
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

    # Story 3.fix: the raw identifier is required to send outbound
    # messages (Twilio needs E.164). Stored alongside the hash —
    # `primary_identifier_hash` is the unique-lookup key, this
    # column is the payload-only recipient address.
    #
    # Sec-fix R5: field-level authorization via `field_policies`
    # (below) — the raw value is admin-only on read; viewer /
    # operator generic `:read` paths still get the row but
    # `primary_identifier` is masked. The outbound worker loads it
    # via `authorize?: false` to bypass field policies for internal
    # consumption.
    attribute :primary_identifier, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :notes_summary, :string do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    # ADR-024: true when the Identity row was auto-created from an
    # inbound webhook with no prior operator confirmation. Operator
    # can promote via `:update_profile`.
    attribute :provisional?, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    attribute :discovered_via, :atom do
      allow_nil?(true)
      constraints(one_of: [:inbound_webhook])
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
      # FK set exclusively via `change(relate_actor(:created_by))` on
      # :register_identity. Marked non-writable so a future caller
      # adding `:created_by_id` to an accept list cannot bypass the
      # actor-relation pattern.
      attribute_writable?(false)
      public?(true)
    end
  end
end
