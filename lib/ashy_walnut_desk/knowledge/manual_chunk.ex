defmodule AshyWalnutDesk.Knowledge.ManualChunk do
  @moduledoc """
  Derived chunk rows for Manual retrieval (story 5.3). Rebuilt by
  `Jobs.ChunkAndEmbedWorker` on every Manual revision; not
  paper-trailed and hard-pruned when superseded (documented ADR-019
  exception — content is reconstructible from Manual versions, and
  retrieval provenance keys on `{manual_id, revision, position,
  content_hash}` which stays resolvable against version history).
  """

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Knowledge,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  alias AshyWalnutDesk.Knowledge.Checks.FromIndexingWorker

  @embedding_dimension Application.compile_env(:ashy_walnut_desk, :embedding_dimension, 1024)

  postgres do
    table("manual_chunks")
    repo(AshyWalnutDesk.Repo)

    references do
      reference(:manual, on_delete: :delete)
    end

    custom_indexes do
      index([:manual_id, :revision, :position], unique: true)
    end
  end

  actions do
    default_accept([])

    read :read do
      primary?(true)
    end

    create :stage do
      accept([:manual_id, :revision, :position, :content, :content_hash])
    end

    update :stamp_embedding do
      accept([:embedding, :embedder])
      require_atomic?(false)
      change(set_attribute(:embedded_at, &DateTime.utc_now/0))
    end

    destroy :prune do
      accept([])
    end
  end

  policies do
    # Inspection surface: admins only. The Retriever and the indexing
    # worker read with authorize?: false inside internal paths.
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action([:stage, :stamp_embedding, :prune]) do
      authorize_if(FromIndexingWorker)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :revision, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :position, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      allow_nil?(false)
      sensitive?(true)
      constraints(max_length: 2_000)
      public?(true)
    end

    attribute :content_hash, :string do
      allow_nil?(false)
      constraints(max_length: 64)
      public?(true)
    end

    attribute :embedding, :vector do
      allow_nil?(true)
      constraints(dimensions: @embedding_dimension)
      public?(true)
    end

    attribute :embedder, :string do
      allow_nil?(true)
      constraints(max_length: 120)
      public?(true)
    end

    attribute :embedded_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :manual, AshyWalnutDesk.Knowledge.Manual do
      allow_nil?(false)
      attribute_writable?(true)
    end
  end
end
