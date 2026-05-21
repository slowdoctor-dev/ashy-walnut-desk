defmodule AshyWalnutDesk.Knowledge.PersonaTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Persona

  test "create enforces required fields and slug uniqueness" do
    admin = AccountsFixtures.create_user(:admin)

    attrs = %{
      name: "Default Persona",
      slug: "default-persona",
      system_prompt: String.duplicate("A", 64),
      disclosure_text: "AI-assisted draft.",
      guardrail_notes: "Never promise outcomes.",
      status: :active
    }

    assert {:ok, persona} = Ash.create(Persona, attrs, action: :create, actor: admin)
    assert persona.slug == "default-persona"
    assert persona.status == :active

    assert {:error, _} = Ash.create(Persona, attrs, action: :create, actor: admin)
  end

  test "update does not accept slug changes" do
    admin = AccountsFixtures.create_user(:admin)

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "After Hours",
          slug: "after-hours",
          system_prompt: String.duplicate("B", 64),
          disclosure_text: "Draft prepared with AI assistance."
        },
        action: :create,
        actor: admin
      )

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(
               persona,
               %{
                 slug: "renamed",
                 name: "After Hours Updated"
               },
               action: :update,
               actor: admin
             )
  end
end
