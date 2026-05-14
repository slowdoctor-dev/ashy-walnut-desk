defmodule AshyWalnutDesk.Accounts.Changes.AssignFirstUserAdminTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Repo

  setup do
    Repo.query!("TRUNCATE TABLE users_versions, users, tokens CASCADE")
    :ok
  end

  test "first sign-in with magic link becomes admin" do
    {:ok, user} = sign_in_with_magic_link("first-admin@example.com")

    assert user.role == :admin
  end

  test "subsequent sign-in with magic link becomes operator" do
    {:ok, _admin} = sign_in_with_magic_link("admin-seed@example.com")
    {:ok, operator} = sign_in_with_magic_link("second-operator@example.com")

    assert operator.role == :operator
  end

  defp sign_in_with_magic_link(email) do
    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    Ash.create(User, %{token: token}, action: :sign_in_with_magic_link, authorize?: false)
  end
end
