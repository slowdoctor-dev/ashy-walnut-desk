defmodule AshyWalnutDesk.Accounts.User do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshPaperTrail.Resource]

  alias Ash.Changeset
  alias AshyWalnutDesk.Accounts.Changes.AssignFirstUserAdmin

  postgres do
    table("users")
    repo(AshyWalnutDesk.Repo)

    custom_indexes do
      index([:role], unique: true, name: "users_one_admin_idx", where: "role = 'admin'")
    end
  end

  paper_trail do
    change_tracking_mode(:changes_only)
    store_action_name?(true)
  end

  actions do
    defaults([:read])

    create :register do
      accept([:email, :role])
      upsert?(true)
      upsert_identity(:unique_email)
      upsert_fields([:email])
    end

    read :get_by_email do
      get?(true)
      argument(:email, :ci_string, allow_nil?: false)
      filter(expr(email == ^arg(:email)))
    end

    create :sign_in_with_magic_link do
      argument :token, :string do
        allow_nil?(false)
      end

      argument :remember_me, :boolean do
        allow_nil?(true)
      end

      upsert?(true)
      upsert_identity(:unique_email)
      upsert_fields([:email])

      change(AshAuthentication.Strategy.MagicLink.SignInChange)
      change(AssignFirstUserAdmin)

      change(
        {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
         strategy_name: :remember_me}
      )

      metadata :token, :string do
        allow_nil?(false)
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil?(false)
      end

      run(AshAuthentication.Strategy.MagicLink.Request)
    end

    update :assign_role do
      accept([:role])
      require_atomic?(false)
    end

    update :mark_signed_in do
      accept([])
      change(set_attribute(:last_signed_in_at, &DateTime.utc_now/0))
      require_atomic?(false)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(expr(id == ^actor(:id)))
    end

    policy action(:assign_role) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end

    policy action(:request_magic_link) do
      authorize_if(always())
    end

    policy action(:sign_in_with_magic_link) do
      authorize_if(always())
    end
  end

  authentication do
    session_identifier(:jti)

    tokens do
      enabled?(true)
      token_resource(AshyWalnutDesk.Accounts.Token)
      signing_secret(AshyWalnutDesk.Accounts.User.JwtSecret)
    end

    strategies do
      magic_link do
        identity_field(:email)
        registration_enabled?(true)
        require_interaction?(true)
        sender(AshyWalnutDesk.Accounts.User.Senders.SendMagicLinkEmail)
      end
    end
  end

  identities do
    identity(:unique_email, [:email])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :email_hash, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :role, :atom do
      constraints(one_of: [:admin, :operator])
      default(:operator)
      allow_nil?(false)
      public?(true)
    end

    attribute(:confirmed_at, :utc_datetime_usec)
    attribute(:last_signed_in_at, :utc_datetime_usec)

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  changes do
    change(
      before_action(fn changeset, _ctx ->
        email = Changeset.get_attribute(changeset, :email)

        if is_nil(email) do
          changeset
        else
          normalized = email |> to_string() |> String.trim() |> String.downcase()
          salt = Application.fetch_env!(:ashy_walnut_desk, :identifier_hash_salt)
          hash = :crypto.hash(:sha256, normalized <> salt) |> Base.encode16(case: :lower)
          Changeset.force_change_attribute(changeset, :email_hash, hash)
        end
      end),
      on: [:create, :update]
    )
  end

  defmodule Senders.SendMagicLinkEmail do
    @moduledoc false

    use AshAuthentication.Sender
    use AshyWalnutDeskWeb, :verified_routes
    alias AshyWalnutDesk.Accounts.Emails

    @impl true
    def send(user_or_email, token, _opts) do
      Emails.deliver_magic_link(
        user_or_email,
        url(~p"/auth/user/magic_link/?token=#{token}")
      )
    end
  end

  defmodule JwtSecret do
    @moduledoc false

    use AshAuthentication.Secret

    @impl true
    def secret_for([:authentication, :tokens, :signing_secret], _resource, _opts, _context) do
      {:ok, System.get_env("ASH_AUTHENTICATION_SECRET") || "dev-only-secret"}
    end
  end
end
