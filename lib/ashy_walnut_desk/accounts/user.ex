defmodule AshyWalnutDesk.Accounts.User do
  @moduledoc false

  use Ash.Resource,
    otp_app: :ashy_walnut_desk,
    domain: AshyWalnutDesk.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshPaperTrail.Resource]

  alias Ash.Changeset
  alias AshyWalnutDesk.Accounts.Changes.{AssignFirstUserAdmin, RegistrationGate}

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
    sensitive_attributes(:redact)
    version_extensions(authorizers: [Ash.Policy.Authorizer])
    mixin(AshyWalnutDesk.AdminOnlyVersions)
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

      upsert?(true)
      upsert_identity(:unique_email)
      upsert_fields([:email])

      change(AshAuthentication.Strategy.MagicLink.SignInChange)
      change(AssignFirstUserAdmin)
      change(RegistrationGate)

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

    # :register is a test-only fixture action. Production registration
    # flows through :sign_in_with_magic_link, which runs
    # AssignFirstUserAdmin to set the role server-side. Forbidding
    # :register prevents the :role attribute (still accepted for test
    # fixtures) from becoming an elevation vector if a future caller
    # forgets to pass authorize?: false.
    policy action(:register) do
      forbid_if(always())
    end

    policy action(:request_magic_link) do
      authorize_if(always())
    end

    policy action(:sign_in_with_magic_link) do
      authorize_if(always())
    end
  end

  authentication do
    # `:jti` keys the LV session value on the per-token JWT id, so
    # per-session revocation actually invalidates the cookie. The
    # Phase 0 `:unsafe` workaround for TO-1 is gone: the upstream
    # `LiveSession.generate_session/3` jti-stripping bug is now
    # sidestepped by `AshyWalnutDeskWeb.LiveUserAuth.on_mount/4`
    # reading the cookie session directly (ADR-020). See
    # `specs/security/known-trade-offs.md` TO-1.
    session_identifier(:jti)

    tokens do
      enabled?(true)
      token_resource(AshyWalnutDesk.Accounts.Token)
      signing_secret(AshyWalnutDesk.Accounts.User.JwtSecret)
      # F3: session tokens persisted + presence-checked on every
      # authenticated request. Without `store_all_tokens?(true)`, the
      # session JWT issued at sign-in isn't written to the Token
      # table at all — so `require_token_presence_for_authentication?`
      # blocks every request (no row to find). Without
      # `require_token_presence_for_authentication?(true)`, sign-out
      # clears the cookie for *this* browser but a captured cookie
      # remains valid until the JWT naturally expires (default 14
      # days). Together they make sign-out → Token row revoke → all
      # subsequent replays fail. Cost: one extra Token-table read per
      # authenticated request, mitigated by the daily
      # `:expunge_tokens` AshOban trigger keeping the table small
      # (TO-3 resolution).
      store_all_tokens?(true)
      require_token_presence_for_authentication?(true)
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
      constraints(one_of: [:admin, :operator, :viewer])
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
      # Link to the MagicSignInLive page (from magic_sign_in_route), not the
      # /auth/user/magic_link callback. The LiveView renders a Phoenix.HTML
      # form with the CSRF token. Pointing the email at the callback URL
      # served `AshAuthentication.Strategy.MagicLink`'s upstream EEx fallback
      # form which omits `_csrf_token`, breaking sign-in in the browser.
      Emails.deliver_magic_link(user_or_email, url(~p"/magic_link/#{token}"))
    end
  end

  defmodule JwtSecret do
    @moduledoc false

    use AshAuthentication.Secret

    @impl true
    def secret_for([:authentication, :tokens, :signing_secret], _resource, _opts, _context) do
      # Read from app env (set in config/runtime.exs). Prod runtime block
      # raises if missing and rejects values < 64 bytes; dev/test get a
      # dev-only fallback set at the top of runtime.exs. Same shape as
      # :identifier_hash_salt — one secret-read path across all envs.
      {:ok, Application.fetch_env!(:ashy_walnut_desk, :ash_authentication_secret)}
    end
  end
end
