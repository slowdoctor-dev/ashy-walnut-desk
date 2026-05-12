defmodule AshyWalnutDesk.Accounts.Token do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("tokens")
    repo(AshyWalnutDesk.Repo)
  end

  actions do
    defaults([:read])

    read :expired do
      filter(expr(expires_at < now()))
    end

    read :get_token do
      get?(true)
      argument(:token, :string, sensitive?: true)
      argument(:jti, :string, sensitive?: true)
      argument(:purpose, :string)

      prepare(AshAuthentication.TokenResource.GetTokenPreparation)
    end

    action :revoked?, :boolean do
      argument(:token, :string, sensitive?: true)
      argument(:jti, :string, sensitive?: true)

      run(AshAuthentication.TokenResource.IsRevoked)
    end

    create :revoke_token do
      accept([:extra_data])
      argument(:token, :string, allow_nil?: false, sensitive?: true)
      change(AshAuthentication.TokenResource.RevokeTokenChange)
    end

    create :revoke_jti do
      accept([:extra_data])
      argument(:subject, :string, allow_nil?: false, sensitive?: true)
      argument(:jti, :string, allow_nil?: false, sensitive?: true)
      change(AshAuthentication.TokenResource.RevokeJtiChange)
    end

    create :store_token do
      accept([:extra_data, :purpose])
      argument(:token, :string, allow_nil?: false, sensitive?: true)
      change(AshAuthentication.TokenResource.StoreTokenChange)
    end

    destroy :expunge_expired do
      change(filter(expr(expires_at < now())))
    end

    update :revoke_all_stored_for_subject do
      accept([:extra_data])
      argument(:subject, :string, allow_nil?: false, sensitive?: true)
      change(AshAuthentication.TokenResource.RevokeAllStoredForSubjectChange)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    policy always() do
      forbid_if(always())
    end
  end

  attributes do
    attribute :jti, :string do
      primary_key?(true)
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :subject, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :expires_at, :utc_datetime do
      allow_nil?(false)
      public?(true)
    end

    attribute :purpose, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :extra_data, :map do
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end
end
