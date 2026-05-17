defmodule Mix.Tasks.AuditVerifyTest do
  use AshyWalnutDesk.DataCase, async: false
  import ExUnit.CaptureIO

  alias AshyWalnutDesk.Interaction.AuditEvent
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Repo
  require Ash.Query

  test "audit.verify exits zero on intact chain and non-zero on tamper" do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 6)

    {:ok, _} = Ash.update(action, %{}, action: :execute, actor: operator)

    Mix.Task.reenable("audit.verify")

    ok_output =
      capture_io(fn ->
        Mix.Task.run("audit.verify")
      end)

    assert ok_output =~ "audit.verify ok"

    [event | _] =
      AuditEvent
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(authorize?: false)

    event_id_bin = Ecto.UUID.dump!(event.id)

    assert %{num_rows: 1} =
             Repo.query!("UPDATE audit_events SET hash = $1 WHERE id = $2", [
               "broken-hash",
               event_id_bin
             ])

    Mix.Task.reenable("audit.verify")

    bad_output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> Mix.Task.run("audit.verify") end
      end)

    assert bad_output =~ "broken event_id=#{event.id}"
  end
end
