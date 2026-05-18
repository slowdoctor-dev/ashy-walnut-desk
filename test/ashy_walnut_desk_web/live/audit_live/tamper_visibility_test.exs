defmodule AshyWalnutDeskWeb.AuditLive.TamperVisibilityTest do
  @moduledoc """
  Story 3.7 AC4 — a tampered audit row is visually distinguishable
  in the LV viewer (status `:broken`) and the same scenario also
  causes `mix audit.verify` to exit non-zero. Both signals stay
  in lockstep so an admin reading the UI sees the same condition
  a CI check would catch.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.{AuditChain, AuditEvent}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Repo
  require Ash.Query

  defp sign_in_as_admin(conn) do
    email = "tamper-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), user}
  end

  test "tampered row renders :broken; AuditChain.walk also reports broken", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)

    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain(admin: admin)

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, operator)

    # Tamper: overwrite the hash of the second event (draft_started).
    [_first, second | _] =
      AuditEvent
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.sort([{:inserted_at, :asc}, {:id, :asc}])
      |> Ash.Query.filter(chain_topic == ^to_string(inbox.id))
      |> Ash.read!(authorize?: false)

    {:ok, dump} = Ecto.UUID.dump(second.id)

    Repo.query!("UPDATE audit_events SET hash = $1 WHERE id = $2", [
      "tampered-hash",
      dump
    ])

    # CLI-equivalent: walk reports broken at the tampered row.
    assert {:error, {:broken_at, broken_id}} = AuditChain.walk(to_string(inbox.id))
    assert broken_id == second.id

    # UI: tampered row carries data-status="broken" and downstream
    # rows propagate the broken state too (continuity_status
    # short-circuits once any prior row breaks).
    {:ok, _view, html} = live(conn, ~p"/audit/chain?topic=#{inbox.id}")

    rows = Floki.parse_fragment!(html) |> Floki.find("[data-role=audit-row]")
    statuses = Enum.map(rows, &Floki.attribute(&1, "data-status"))

    assert ["ok"] in statuses
    assert ["broken"] in statuses

    # The first row should still be :ok (the tampered row is the
    # second one); the second and every subsequent row must show
    # :broken.
    [first | rest] = statuses
    assert first == ["ok"]
    assert Enum.all?(rest, &(&1 == ["broken"]))
  end
end
