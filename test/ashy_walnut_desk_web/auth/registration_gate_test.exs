defmodule AshyWalnutDeskWeb.Auth.RegistrationGateTest do
  @moduledoc """
  F1 regression — magic-link self-registration is gated on
  `:registration_enabled?` application env. Default false; dev/test
  flip it on for local workflow; deployers opt in via
  `AWD_REGISTRATION_ENABLED=1` (read by `config/runtime.exs`).

  Test strategy: temporarily flip the env to `false` inside the
  test, then exercise the magic-link sign-in path for a fresh
  email and a known email. Fresh email must be rejected; known
  email must succeed (sign-in for existing users isn't gated).
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Ash.Expr
  require Ash.Query

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User

  setup do
    original = Application.get_env(:ashy_walnut_desk, :registration_enabled?)
    Application.put_env(:ashy_walnut_desk, :registration_enabled?, false)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :registration_enabled?, original) end)
    :ok
  end

  test "unknown email is refused when registration is disabled", %{conn: conn} do
    email = "registration-gate-unknown-#{System.unique_integer([:positive])}@example.com"

    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    response_conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})

    # Failure manifests as a non-redirect render (re-render of the
    # sign-in form with errors). The exact status / template differs
    # across AshAuthenticationPhoenix versions; the load-bearing
    # assertion is that the user was NOT created.
    refute redirected_to(response_conn) == "/",
           "registration disabled, but magic-link sign-in succeeded for new email"

    exists? =
      User
      |> Ash.Query.filter(expr(email == ^email))
      |> Ash.exists(authorize?: false)

    refute match?({:ok, true}, exists?),
           "RegistrationGate did not block creation of new user with registration disabled"
  end

  test "existing user signs in normally when registration is disabled", %{conn: conn} do
    email = "registration-gate-known-#{System.unique_integer([:positive])}@example.com"

    # Pre-seed the user. Test env has `register` policy `forbid_if always()`,
    # so we use `authorize?: false` — same pattern other tests use.
    {:ok, _user} =
      Ash.create(User, %{email: email, role: :operator},
        action: :register,
        authorize?: false
      )

    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    response_conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})

    assert redirected_to(response_conn) == "/",
           "existing user could not sign in with registration disabled — gate is too aggressive"
  end
end
