defmodule Mix.Tasks.AuditVerifyTest do
  use AshyWalnutDesk.DataCase, async: false
  import ExUnit.CaptureIO
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, AuditEvent, Channel, Conversation, Draft, Inbox}
  alias AshyWalnutDesk.Repo

  test "audit.verify exits zero on intact chain and non-zero on tamper" do
    %{operator: operator, draft: draft, action: action} = seed_approved_chain()

    {:ok, _draft} =
      Ash.update(draft, %{approved_at: DateTime.add(DateTime.utc_now(), -6, :second)},
        action: :edit_draft,
        actor: operator
      )

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

  defp seed_approved_chain do
    admin = create_user(:admin)
    operator = create_user(:operator)
    unique = System.unique_integer([:positive])

    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: "Identity #{unique}", primary_identifier: "+1555#{unique}"},
        action: :register_identity,
        actor: admin
      )

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "Thread", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: operator
      )

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{
          conversation_id: conversation.id,
          status: :drafting,
          summary: "Need response",
          recorded_by_id: operator.id
        },
        action: :record_inbox,
        actor: operator
      )

    {:ok, draft} =
      Ash.create(
        Draft,
        %{inbox_id: inbox.id, body: "Draft body", compensation_body: "Comp", status: :drafting},
        action: :compose_draft,
        actor: operator
      )

    {:ok, approved} = Ash.update(draft, %{}, action: :approve, actor: operator)

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!(authorize?: false)

    %{operator: operator, draft: approved, action: action}
  end

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
end
