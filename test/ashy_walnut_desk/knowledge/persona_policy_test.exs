defmodule AshyWalnutDesk.Knowledge.PersonaPolicyTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Persona

  test "admin and operator can read; viewer cannot" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    viewer = AccountsFixtures.create_user(:viewer)

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Policy Persona",
          slug: "policy-persona",
          system_prompt: String.duplicate("C", 64),
          disclosure_text: "AI-assisted response draft."
        },
        action: :create,
        actor: admin
      )

    assert {:ok, admin_rows} = Ash.read(Persona, action: :read, actor: admin)
    assert Enum.any?(admin_rows, &(&1.id == persona.id))

    assert {:ok, operator_rows} = Ash.read(Persona, action: :read, actor: operator)
    assert Enum.any?(operator_rows, &(&1.id == persona.id))

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Persona, action: :read, actor: viewer)
  end

  test "field policies hide sensitive internals from operators" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Field Policy",
          slug: "field-policy",
          system_prompt: String.duplicate("D", 64),
          disclosure_text: "Generated with AI.",
          guardrail_notes: "No guarantees.",
          model_override: "claude-sonnet-4-6"
        },
        action: :create,
        actor: admin
      )

    assert {:ok, admin_row} = Ash.get(Persona, persona.id, actor: admin)
    assert is_binary(admin_row.system_prompt)
    assert is_binary(admin_row.disclosure_text)

    assert {:ok, operator_row} = Ash.get(Persona, persona.id, actor: operator)
    assert %Ash.ForbiddenField{} = operator_row.system_prompt
    assert %Ash.ForbiddenField{} = operator_row.disclosure_text
    assert %Ash.ForbiddenField{} = operator_row.guardrail_notes
    assert %Ash.ForbiddenField{} = operator_row.model_override
  end

  test "only admin can mutate" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Mutations",
          slug: "mutations",
          system_prompt: String.duplicate("E", 64),
          disclosure_text: "AI-assisted message."
        },
        action: :create,
        actor: admin
      )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(persona, %{name: "Nope"}, action: :update, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(persona, %{}, action: :archive, actor: operator)
  end
end
