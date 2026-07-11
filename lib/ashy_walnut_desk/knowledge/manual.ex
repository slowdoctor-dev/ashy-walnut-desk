defmodule AshyWalnutDesk.Knowledge.Manual do
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
  alias AshyWalnutDesk.Knowledge.Changes.EnqueueIndexing

  postgres do
    table("manuals")
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

    create :author do
      accept([:title, :slug, :body])
      validate(string_length(:title, min: 1, max: 200))
      validate(string_length(:body, min: 1, max: 64_000))
      change(EnqueueIndexing)
    end

    # Content revision. Bumps `revision` so derived ManualChunk rows
    # (story 5.3) can tell current content from stale content. Slug is
    # deliberately immutable — retrieval provenance references it.
    update :revise do
      accept([:title, :body])
      require_atomic?(false)
      validate(string_length(:title, min: 1, max: 200))
      validate(string_length(:body, min: 1, max: 64_000))
      change(&bump_revision/2)
      change(EnqueueIndexing)
    end

    # Archive is a retrieval-visibility flip, not a delete: archived
    # manuals stay readable (read_with_archived) and recoverable, but
    # the Retriever (story 5.4) never serves excerpts from them.
    update :archive do
      accept([])
      require_atomic?(false)
      change(set_attribute(:status, :archived))
    end

    update :restore do
      accept([])
      require_atomic?(false)
      change(set_attribute(:status, :active))
      change(set_attribute(:deleted_at, nil))
    end

    update :soft_delete do
      accept([])
      require_atomic?(false)
      change(SoftDelete)
      change(set_attribute(:status, :archived))
    end
  end

  policies do
    policy action(:read) do
      authorize_if(AdminOrOperator)
    end

    policy action(:read_with_archived) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:author) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action([:revise, :archive, :restore, :soft_delete]) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end

  field_policies do
    # Unlike Persona internals (admin-only), Manual bodies exist FOR
    # operators — they are the deployment's reference material.
    field_policy :body do
      authorize_if(AdminOrOperator)
    end

    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      constraints(max_length: 200)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      constraints(max_length: 120, match: ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
      public?(true)
    end

    attribute :body, :string do
      allow_nil?(false)
      sensitive?(true)
      constraints(max_length: 64_000)
      public?(true)
    end

    attribute :revision, :integer do
      allow_nil?(false)
      default(1)
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

  defp bump_revision(changeset, _context) do
    current = Ash.Changeset.get_data(changeset, :revision) || 1
    Ash.Changeset.force_change_attribute(changeset, :revision, current + 1)
  end
end
