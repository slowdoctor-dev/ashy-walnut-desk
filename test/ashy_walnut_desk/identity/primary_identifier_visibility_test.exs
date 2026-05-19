defmodule AshyWalnutDesk.Identity.PrimaryIdentifierVisibilityTest do
  @moduledoc """
  Sec-fix R5 — `Identity.primary_identifier` is marked
  `public?: false` so generic read paths do NOT return the raw
  E.164. Verifies the worker can still get it via the internal
  load path, but viewer / operator generic reads do not surface it.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.InteractionFixtures

  defp seeded_identity(admin) do
    InteractionFixtures.seed_identity(admin,
      display_name: "Visibility test",
      primary_identifier: "+15558881234"
    )
  end

  test "viewer cannot read raw primary_identifier via generic :read" do
    admin = AccountsFixtures.create_user(:admin)
    viewer = AccountsFixtures.create_user(:viewer)
    identity = seeded_identity(admin)

    {:ok, reloaded} = Ash.get(Identity, identity.id, actor: viewer)

    # Field policy masks the raw value for non-admin actors. Ash
    # surfaces a `%Ash.ForbiddenField{}` sentinel instead of the
    # actual string.
    assert match?(%Ash.ForbiddenField{}, reloaded.primary_identifier),
           "expected ForbiddenField, got: #{inspect(reloaded.primary_identifier)}"

    assert match?(%Ash.ForbiddenField{}, reloaded.primary_identifier_hash),
           "expected ForbiddenField, got: #{inspect(reloaded.primary_identifier_hash)}"
  end

  test "operator cannot read raw primary_identifier via generic :read" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = seeded_identity(admin)

    {:ok, reloaded} = Ash.get(Identity, identity.id, actor: operator)

    assert match?(%Ash.ForbiddenField{}, reloaded.primary_identifier),
           "expected ForbiddenField, got: #{inspect(reloaded.primary_identifier)}"

    assert match?(%Ash.ForbiddenField{}, reloaded.primary_identifier_hash),
           "expected ForbiddenField, got: #{inspect(reloaded.primary_identifier_hash)}"
  end

  test "admin CAN read raw primary_identifier" do
    admin = AccountsFixtures.create_user(:admin)
    identity = seeded_identity(admin)

    {:ok, reloaded} = Ash.get(Identity, identity.id, actor: admin)
    assert reloaded.primary_identifier == "+15558881234"
    refute is_nil(reloaded.primary_identifier_hash)
  end

  test "outbound worker path (authorize?: false + explicit load) still gets the raw value" do
    admin = AccountsFixtures.create_user(:admin)
    identity = seeded_identity(admin)

    {:ok, loaded} =
      Ash.get(Identity, identity.id,
        authorize?: false,
        load: [:primary_identifier]
      )

    assert loaded.primary_identifier == "+15558881234"
  end
end
