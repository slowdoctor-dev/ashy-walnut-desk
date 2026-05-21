defmodule AshyWalnutDesk.Knowledge.PersonaPaperTrailTest do
  use AshyWalnutDesk.DataCase, async: false

  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Persona

  test "archive/recover and version rows are recorded with redacted sensitive changes" do
    admin = AccountsFixtures.create_user(:admin)

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Paper Trail",
          slug: "paper-trail",
          system_prompt: String.duplicate("F", 64),
          disclosure_text: "This draft was generated with AI assistance.",
          guardrail_notes: "Avoid regulated claims."
        },
        action: :create,
        actor: admin
      )

    {:ok, updated} =
      Ash.update(
        persona,
        %{
          system_prompt: String.duplicate("G", 64),
          disclosure_text: "AI-assisted response draft."
        },
        action: :update,
        actor: admin
      )

    {:ok, archived} = Ash.update(updated, %{}, action: :archive, actor: admin)
    refute is_nil(archived.deleted_at)
    assert archived.status == :archived

    {:ok, recovered} = Ash.update(archived, %{}, action: :recover, actor: admin)
    assert is_nil(recovered.deleted_at)
    assert recovered.status == :active

    versions =
      Persona.Version
      |> Ash.Query.filter(version_source_id == ^persona.id)
      |> Ash.read!(action: :read, authorize?: false)

    assert length(versions) >= 4

    assert Enum.any?(versions, fn version ->
             Map.get(version.changes || %{}, "system_prompt") == "REDACTED"
           end)

    assert Enum.any?(versions, fn version ->
             Map.get(version.changes || %{}, "disclosure_text") == "REDACTED"
           end)
  end
end
