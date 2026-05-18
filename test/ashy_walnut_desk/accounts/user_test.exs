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

  test "roles include admin/operator/viewer/system enum" do
    # `:system` added in story 3.3 (ADR-024) for the inbound-webhook
    # system actor. Magic-link sign-in is blocked for `system+%`
    # addresses by `RegistrationGate`.
    attr = Info.attribute(User, :role)
    assert attr.constraints[:one_of] == [:admin, :operator, :viewer, :system]
  end

  test "unauthenticated can request magic link" do
    assert {:ok, true} =
             Ash.can({User, :request_magic_link, %{email: "test@example.com"}}, actor: nil)
  end

  test ":register is forbidden by default and only callable with authorize?: false" do
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(User, %{email: "blocked@example.com"}, action: :register)

    assert {:ok, _} =
             Ash.create(User, %{email: "allowed@example.com"},
               action: :register,
               authorize?: false
             )
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

    {:ok, _demoted} =
      Ash.update(admin, %{role: :operator}, action: :assign_role, actor: admin)

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

    {:ok, _demoted} =
      Ash.update(admin, %{role: :operator}, action: :assign_role, actor: admin)

    {:ok, _updated} = Ash.update(user, %{role: :admin}, action: :assign_role, actor: admin)

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == user.id))

    assert versions != []
  end

  test "sensitive attributes are redacted in version rows" do
    email = "redact-target@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email}, action: :register, authorize?: false)

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == user.id))

    assert versions != []

    for v <- versions do
      assert v.changes["email"] in [nil, "REDACTED"]
      assert v.changes["email_hash"] in [nil, "REDACTED"]
      refute v.changes["email"] == email
      refute v.changes["email_hash"] == user.email_hash

      # Also assert no sensitive plaintext bleeds into other persisted
      # payload columns. `version_action_inputs` is only present when
      # `store_action_inputs?(true)` is configured; this fence catches any
      # future flip-to-true that forgets to scrub the same way `changes` does.
      if Map.has_key?(v, :version_action_inputs) do
        for {_k, value} <- v.version_action_inputs || %{} do
          rendered = inspect(value)
          refute rendered =~ email
          refute rendered =~ user.email_hash
        end
      end
    end
  end

  test "Version reads require an admin actor" do
    {:ok, admin} =
      Ash.create(User, %{email: "version-admin@example.com", role: :admin},
        action: :register,
        authorize?: false
      )

    {:ok, operator} =
      Ash.create(User, %{email: "version-operator@example.com"},
        action: :register,
        authorize?: false
      )

    assert {:ok, _versions} = Ash.read(Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: operator)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: nil)
  end
end
