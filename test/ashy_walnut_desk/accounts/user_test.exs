defmodule AshyWalnutDesk.Accounts.UserTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Accounts.User.Version

  test "email_hash is deterministic from normalized email + salt" do
    salt = Application.fetch_env!(:ashy_walnut_desk, :identifier_hash_salt)

    {:ok, user1} =
      Ash.create(User, %{email: " Test@Example.com "}, action: :register, authorize?: false)

    {:ok, user2} =
      Ash.create(User, %{email: "test@example.com"}, action: :register, authorize?: false)

    expected = :crypto.hash(:sha256, "test@example.com" <> salt) |> Base.encode16(case: :lower)

    assert user1.email_hash == expected
    assert user2.email_hash == expected
  end

  test "roles include admin/operator enum" do
    attr = Info.attribute(User, :role)
    assert attr.constraints[:one_of] == [:admin, :operator]
  end

  test "unauthenticated can request magic link" do
    assert {:ok, true} =
             Ash.can({User, :request_magic_link, %{email: "test@example.com"}}, actor: nil)
  end

  test "operator cannot assign role" do
    {:ok, operator} =
      Ash.create(User, %{email: "op@example.com", role: :operator},
        action: :register,
        authorize?: false
      )

    {:ok, target} =
      Ash.create(User, %{email: "target-op@example.com"}, action: :register, authorize?: false)

    assert {:error, _} =
             Ash.update(target, %{role: :admin}, action: :assign_role, actor: operator)
  end

  test "admin can assign role" do
    {:ok, admin} =
      Ash.create(User, %{email: "admin@example.com", role: :admin},
        action: :register,
        authorize?: false
      )

    {:ok, target} =
      Ash.create(User, %{email: "target-admin@example.com"}, action: :register, authorize?: false)

    assert {:ok, _updated} =
             Ash.update(target, %{role: :admin}, action: :assign_role, actor: admin)
  end

  test "assign_role update creates paper trail version row" do
    {:ok, admin} =
      Ash.create(User, %{email: "audit-admin@example.com", role: :admin},
        action: :register,
        authorize?: false
      )

    {:ok, user} =
      Ash.create(User, %{email: "audit-user@example.com"}, action: :register, authorize?: false)

    {:ok, _updated} = Ash.update(user, %{role: :admin}, action: :assign_role, actor: admin)

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == user.id))

    assert versions != []
  end
end
