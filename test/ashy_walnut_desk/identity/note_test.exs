defmodule AshyWalnutDesk.Identity.NoteTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Note
  alias AshyWalnutDesk.Identity.Note.Version

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

  defp register_identity(actor) do
    {:ok, identity} =
      Ash.create(
        Identity,
        %{
          display_name: "Alex Doe",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        action: :register_identity,
        actor: actor
      )

    identity
  end

  defp record_note(actor, identity, attrs \\ %{}) do
    Ash.create(
      Note,
      Map.merge(
        %{
          identity_id: identity.id,
          body: "Observation"
        },
        attrs
      ),
      action: :record_note,
      actor: actor
    )
  end

  # AC1 — action surface, ownership link, body-only edit

  test "exposes the documented action surface" do
    action_names = Note |> Info.actions() |> Enum.map(& &1.name) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new([
               :read,
               :read_with_archived,
               :record_note,
               :edit_note,
               :archive,
               :recover
             ]),
             action_names
           )
  end

  test "record_note requires an owning identity" do
    admin = create_user(:admin)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               Note,
               %{body: "Orphan"},
               action: :record_note,
               actor: admin
             )
  end

  test "record_note sets recorded_by from actor and links to identity" do
    operator = create_user(:operator)
    identity = register_identity(operator)

    assert {:ok, note} = record_note(operator, identity, %{body: "Checked vitals"})
    assert note.identity_id == identity.id
    assert note.recorded_by_id == operator.id
    assert note.body == "Checked vitals"
  end

  test "edit_note accepts body only" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    {:ok, note} = record_note(operator, identity)

    assert {:ok, edited} =
             Ash.update(note, %{body: "Updated"},
               action: :edit_note,
               actor: operator
             )

    assert edited.body == "Updated"
    assert edited.recorded_by_id == operator.id
  end

  test "edit_note rejects recorded_by_id as an input (immutable)" do
    operator = create_user(:operator)
    other = create_user(:operator)
    identity = register_identity(operator)
    {:ok, note} = record_note(operator, identity)

    # recorded_by_id is not in the action's `accept` list, so Ash refuses
    # the input outright rather than silently dropping it — proving the
    # attribute is immutable through the public action surface.
    assert {:error, %Ash.Error.Invalid{} = err} =
             Ash.update(
               note,
               %{body: "Updated", recorded_by_id: other.id},
               action: :edit_note,
               actor: operator
             )

    assert Enum.any?(
             err.errors,
             &match?(%Ash.Error.Invalid.NoSuchInput{input: :recorded_by_id}, &1)
           )
  end

  # AC2 — role-based + owner-aware policies

  test "operator and admin can record_note; viewer cannot" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)
    identity = register_identity(admin)

    assert {:ok, _} = record_note(admin, identity)
    assert {:ok, _} = record_note(operator, identity)
    assert {:error, %Ash.Error.Forbidden{}} = record_note(viewer, identity)
  end

  test "viewer can read but cannot edit or archive" do
    admin = create_user(:admin)
    viewer = create_user(:viewer)
    identity = register_identity(admin)
    {:ok, note} = record_note(admin, identity)

    assert {:ok, _list} = Ash.read(Note, actor: viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(note, %{body: "Hacked"},
               action: :edit_note,
               actor: viewer
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(note, %{}, action: :archive, actor: viewer)
  end

  test "another operator cannot edit a note recorded by someone else" do
    owner = create_user(:operator)
    bystander = create_user(:operator)
    identity = register_identity(owner)
    {:ok, note} = record_note(owner, identity)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(note, %{body: "Tampered"},
               action: :edit_note,
               actor: bystander
             )
  end

  test "the recording operator can edit their own note" do
    owner = create_user(:operator)
    identity = register_identity(owner)
    {:ok, note} = record_note(owner, identity, %{body: "Original"})

    assert {:ok, edited} =
             Ash.update(note, %{body: "Owner edit"},
               action: :edit_note,
               actor: owner
             )

    assert edited.body == "Owner edit"
  end

  test "admin can edit any note even if they did not record it" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, note} = record_note(operator, identity, %{body: "Operator note"})

    assert {:ok, edited} =
             Ash.update(note, %{body: "Admin edit"},
               action: :edit_note,
               actor: admin
             )

    assert edited.body == "Admin edit"
  end

  test "another operator cannot archive a note recorded by someone else" do
    owner = create_user(:operator)
    bystander = create_user(:operator)
    identity = register_identity(owner)
    {:ok, note} = record_note(owner, identity)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(note, %{}, action: :archive, actor: bystander)
  end

  test "the recording operator can archive their own note" do
    owner = create_user(:operator)
    identity = register_identity(owner)
    {:ok, note} = record_note(owner, identity)

    assert {:ok, archived} =
             Ash.update(note, %{}, action: :archive, actor: owner)

    refute is_nil(archived.deleted_at)
  end

  test "admin can archive any note" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, note} = record_note(operator, identity)

    assert {:ok, archived} =
             Ash.update(note, %{}, action: :archive, actor: admin)

    refute is_nil(archived.deleted_at)
  end

  test "operator (even the owner) cannot recover; admin can" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, note} = record_note(operator, identity)

    {:ok, archived} = Ash.update(note, %{}, action: :archive, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(archived, %{}, action: :recover, actor: operator)

    assert {:ok, recovered} = Ash.update(archived, %{}, action: :recover, actor: admin)
    assert is_nil(recovered.deleted_at)
  end

  test "unauthenticated callers are denied for read and write actions" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    {:ok, note} = record_note(admin, identity)

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Note, actor: nil)

    # relate_actor(:recorded_by) on a nil actor surfaces as InvalidRelationship
    # rather than Forbidden — either is an unauthenticated write being refused.
    assert {:error, %struct{}} = record_note(nil, identity)
    assert struct in [Ash.Error.Forbidden, Ash.Error.Invalid]

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(note, %{body: "X"}, action: :edit_note, actor: nil)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(note, %{}, action: :archive, actor: nil)
  end

  # AC3 — soft-delete + paper trail redaction + admin-only Version reads

  test "archive sets deleted_at and default read filters archived rows" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, note} = record_note(operator, identity)

    {:ok, archived} = Ash.update(note, %{}, action: :archive, actor: operator)
    refute is_nil(archived.deleted_at)

    {:ok, visible} = Ash.read(Note, actor: admin)
    refute Enum.any?(visible, &(&1.id == note.id))

    {:ok, all} = Ash.read(Note, action: :read_with_archived, actor: admin)
    assert Enum.any?(all, &(&1.id == note.id))
  end

  test "archive is idempotent — second invocation does not change deleted_at" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    {:ok, note} = record_note(admin, identity)

    {:ok, archived_once} = Ash.update(note, %{}, action: :archive, actor: admin)
    {:ok, archived_twice} = Ash.update(archived_once, %{}, action: :archive, actor: admin)

    assert DateTime.compare(archived_once.deleted_at, archived_twice.deleted_at) == :eq
  end

  test "read_with_archived is admin-only" do
    operator = create_user(:operator)
    viewer = create_user(:viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Note, action: :read_with_archived, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Note, action: :read_with_archived, actor: viewer)
  end

  test "body is marked sensitive" do
    %{sensitive?: body_sensitive} = Info.attribute(Note, :body)
    assert body_sensitive
  end

  test "record_note writes a version row that redacts sensitive attributes" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    raw_body = "Confidential observation"

    {:ok, note} = record_note(admin, identity, %{body: raw_body})

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == note.id))

    assert versions != []

    for v <- versions do
      assert v.changes["body"] in [nil, "REDACTED"]
      refute v.changes["body"] == raw_body

      rendered = inspect(v.changes)
      refute rendered =~ raw_body
    end
  end

  test "Version reads require an admin actor" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)
    identity = register_identity(admin)

    {:ok, _note} = record_note(admin, identity)

    assert {:ok, _} = Ash.read(Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: operator)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: viewer)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: nil)
  end
end
