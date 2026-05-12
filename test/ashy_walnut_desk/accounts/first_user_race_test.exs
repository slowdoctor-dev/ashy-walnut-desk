defmodule AshyWalnutDesk.Accounts.FirstUserRaceTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Repo

  setup do
    Repo.query!("TRUNCATE TABLE users_versions, users, tokens")
    :ok
  end

  test "two concurrent first-user sign-ins result in exactly one admin" do
    emails = ["race1@example.com", "race2@example.com"]

    results =
      emails
      |> Task.async_stream(&sign_in_with_magic_link/1, max_concurrency: 2, timeout: 15_000)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    users = Ash.read!(User, authorize?: false)
    roles_by_email = Map.new(users, &{to_string(&1.email), &1.role})

    assert roles_by_email["race1@example.com"] in [:admin, :operator]
    assert roles_by_email["race2@example.com"] in [:admin, :operator]

    admin_count = Enum.count(users, &(&1.role == :admin))
    operator_count = Enum.count(users, &(&1.role == :operator))

    assert admin_count == 1
    assert operator_count == 1
  end

  defp sign_in_with_magic_link(email) do
    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    Ash.create(User, %{token: token}, action: :sign_in_with_magic_link, authorize?: false)
  end
end
