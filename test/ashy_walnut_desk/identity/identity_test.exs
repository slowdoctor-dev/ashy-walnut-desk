defmodule AshyWalnutDesk.Identity.IdentityTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Identity.Version

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{email: "#{role}-#{System.unique_integer([:positive])}@example.com", role: role},
        action: :register,
        authorize?: false
      )

    user
  end

  defp register_identity(actor, attrs \\ %{}) do
    Ash.create(
      Identity,
      Map.merge(
        %{
          display_name: "Alex Doe",
          primary_identifier: "+15551234567"
        },
        attrs
      ),
      action: :register_identity,
      actor: actor
    )
  end

  # AC1 — action surface and policy boundaries

  test "exposes the documented action surface" do
    action_names = Identity |> Info.actions() |> Enum.map(& &1.name) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new([
               :read,
               :read_with_archived,
               :register_identity,
               :update_profile,
               :archive,
               :recover
             ]),
             action_names
           )
  end

  test "operator and admin can register; viewer cannot" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)

    assert {:ok, _} = register_identity(admin, %{display_name: "Admin Reg"})
    assert {:ok, _} = register_identity(operator, %{display_name: "Operator Reg"})

    assert {:error, %Ash.Error.Forbidden{}} =
             register_identity(viewer, %{display_name: "Viewer Reg"})
  end

  test "viewer can read but cannot update_profile or archive" do
    admin = create_user(:admin)
    viewer = create_user(:viewer)

    {:ok, identity} = register_identity(admin)

    assert {:ok, _list} = Ash.read(Identity, actor: viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(identity, %{display_name: "Hacked"},
               action: :update_profile,
               actor: viewer
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(identity, %{}, action: :archive, actor: viewer)
  end

  test "operator cannot recover; admin can" do
    admin = create_user(:admin)
    operator = create_user(:operator)

    {:ok, identity} = register_identity(admin)
    {:ok, archived} = Ash.update(identity, %{}, action: :archive, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(archived, %{}, action: :recover, actor: operator)

    assert {:ok, recovered} = Ash.update(archived, %{}, action: :recover, actor: admin)
    assert is_nil(recovered.deleted_at)
  end

  # AC2 — primary identifier is hashed and never stored raw

  test "primary identifier normalizes formatting and hashes deterministically" do
    # Sec-fix R3: identifier is normalized to bare E.164 (`+` plus
    # digits) before hashing, so different human-friendly formats
    # of the same number collide on the same hash. The original
    # Phase 1 test only trimmed whitespace; now formatting chars
    # (hyphens, spaces, parens) are also stripped.
    salt = Application.fetch_env!(:ashy_walnut_desk, :identifier_hash_salt)
    admin = create_user(:admin)

    {:ok, identity1} =
      register_identity(admin, %{display_name: "Hash A", primary_identifier: " +1-555 123 "})

    {:ok, identity2} =
      register_identity(admin, %{display_name: "Hash B", primary_identifier: "+1 (555) 123"})

    expected =
      :crypto.hash(:sha256, "+1555123" <> salt) |> Base.encode16(case: :lower)

    assert identity1.primary_identifier_hash == expected
    assert identity2.primary_identifier_hash == expected
    assert identity1.primary_identifier == "+1555123"
  end

  test "primary identifier rejects non-E.164 input" do
    admin = create_user(:admin)

    assert {:error, %Ash.Error.Invalid{}} =
             register_identity(admin, %{
               display_name: "Bad",
               primary_identifier: "not a phone number"
             })

    assert {:error, %Ash.Error.Invalid{}} =
             register_identity(admin, %{display_name: "Bad", primary_identifier: "5551234567"})

    assert {:error, %Ash.Error.Invalid{}} =
             register_identity(admin, %{
               display_name: "Bad",
               primary_identifier: "'; DROP TABLE users; --"
             })
  end

  test "primary_identifier and its hash are both stored and marked sensitive" do
    # Story 3.fix: raw `primary_identifier` is required to send
    # outbound (Twilio needs E.164). Stored alongside the hash with
    # `sensitive?: true` so paper-trail and inspect don't leak it.
    attribute_names = Identity |> Info.attributes() |> Enum.map(& &1.name)
    assert :primary_identifier in attribute_names
    assert :primary_identifier_hash in attribute_names

    assert Info.attribute(Identity, :primary_identifier).sensitive?
    assert Info.attribute(Identity, :primary_identifier_hash).sensitive?
  end

  # AC3 — soft-delete + default-filter + recover

  test "archive sets deleted_at and default read filters archived rows" do
    admin = create_user(:admin)
    operator = create_user(:operator)

    {:ok, identity} = register_identity(admin)

    {:ok, archived} = Ash.update(identity, %{}, action: :archive, actor: operator)
    refute is_nil(archived.deleted_at)

    {:ok, visible} = Ash.read(Identity, actor: admin)
    refute Enum.any?(visible, &(&1.id == identity.id))

    {:ok, all} = Ash.read(Identity, action: :read_with_archived, actor: admin)
    assert Enum.any?(all, &(&1.id == identity.id))
  end

  test "archive is idempotent — second invocation does not change deleted_at" do
    admin = create_user(:admin)
    {:ok, identity} = register_identity(admin)

    {:ok, archived_once} = Ash.update(identity, %{}, action: :archive, actor: admin)
    {:ok, archived_twice} = Ash.update(archived_once, %{}, action: :archive, actor: admin)

    assert DateTime.compare(archived_once.deleted_at, archived_twice.deleted_at) == :eq
  end

  test "read_with_archived is admin-only" do
    operator = create_user(:operator)
    viewer = create_user(:viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Identity, action: :read_with_archived, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Identity, action: :read_with_archived, actor: viewer)
  end

  # AC4 — paper trail redaction + admin-only Version reads

  test "register_identity writes a version row that redacts sensitive attributes" do
    admin = create_user(:admin)

    {:ok, identity} =
      register_identity(admin, %{
        display_name: "Redacted Name",
        primary_identifier: "+15550009999"
      })

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == identity.id))

    assert versions != []

    raw_identifier = "+15550009999"

    for v <- versions do
      assert v.changes["display_name"] in [nil, "REDACTED"]
      assert v.changes["primary_identifier_hash"] in [nil, "REDACTED"]
      # Story 3.fix: the raw `primary_identifier` is now persisted
      # to support outbound sends. PaperTrail's `sensitive_attributes(:redact)`
      # MUST hide it from version diffs — leaking the E.164 in the
      # diff would defeat the `sensitive?: true` flag.
      assert v.changes["primary_identifier"] in [nil, "REDACTED"]

      refute v.changes["display_name"] == "Redacted Name"
      refute v.changes["primary_identifier_hash"] == identity.primary_identifier_hash
      refute v.changes["primary_identifier"] == raw_identifier

      rendered = inspect(v.changes)
      refute rendered =~ raw_identifier
      refute rendered =~ identity.primary_identifier_hash
    end
  end

  test "Version reads require an admin actor" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)

    {:ok, _identity} = register_identity(admin)

    assert {:ok, _} = Ash.read(Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: operator)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: viewer)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: nil)
  end
end
