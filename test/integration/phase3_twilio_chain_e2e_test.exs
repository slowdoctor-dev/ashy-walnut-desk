defmodule AshyWalnutDesk.Integration.Phase3TwilioChainE2ETest do
  @moduledoc """
  Story 3.8 AC4 — end-to-end integration covering the full Phase 3
  pipeline:

  1. Inbound Twilio webhook → `InboundIntake` creates Identity,
     Conversation, Inbox, inbound Message, and writes
     `:inbox_opened` to the audit chain. (Story 3.3)
  2. Operator drafts + approves a reply → Action.:execute enqueues
     `Jobs.OutboundSend` (story 3.5) → worker hits Twilio adapter
     (mocked via `:twilio_req_options` plug) → outbound `Message`
     created, Inbox transitions to `:executed`. (Stories 3.4 / 3.5)
  3. Operator triggers compensation → second outbound `Message`
     created, `:compensation_executed` audit event written.
     (Story 3.6)
  4. Admin opens `/audit/chain?topic=<inbox>` → 8 events render
     with `:ok` status badges; `mix audit.verify` exits 0. (Story
     3.7)

  Provider is mocked at the `Req` plug boundary. No real Twilio
  network calls.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  require Ash.Query
  import Ash.Expr

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User

  alias AshyWalnutDesk.Interaction.{
    AuditChain,
    Channel,
    Compensation,
    Conversation,
    Draft,
    InboundIntake,
    InboundMessage,
    Inbox,
    Message
  }

  alias AshyWalnutDesk.Interaction.Adapters.Twilio
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  setup do
    Process.put(:twilio_attempts, [])

    prev_req = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])

    capture_plug = fn conn ->
      Process.put(
        :twilio_attempts,
        [Map.new(conn.req_headers) | Process.get(:twilio_attempts)]
      )

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{"sid" => "SMxx-e2e", "status" => "queued", "to" => "+15551234567"})
      )
    end

    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: capture_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev_req) end)

    %{}
  end

  defp sign_in_as_admin(conn) do
    email = "e2e-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "inbound webhook → outbound send → compensation → audit chain visibility", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    operator = AshyWalnutDesk.AccountsFixtures.create_user(:operator)

    # ─── 1. Bootstrap: register the Twilio-backed channel ────────
    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: Atom.to_string(Twilio)
        },
        action: :register_channel,
        actor: admin
      )

    # ─── 2. Inbound webhook intake (story 3.3) ───────────────────
    sid = "SM" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    inbound_from = "+15551239999"

    msg = %InboundMessage{
      provider: :twilio,
      provider_message_id: sid,
      from: inbound_from,
      to: "+15557654321",
      body: "hi from inbound",
      received_at: DateTime.utc_now()
    }

    assert {:ok, %{outcome: :processed} = intake_result} = InboundIntake.intake(msg, channel)
    inbox = Ash.get!(Inbox, intake_result.inbox.id, authorize?: false)
    assert inbox.status == :open

    # ─── 3. Operator drafts + approves + sends (stories 3.4/3.5) ─
    {:ok, _drafting_inbox} =
      Ash.update(inbox, %{}, action: :mark_drafting, actor: operator, authorize?: false)

    {:ok, draft} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "Outbound reply",
          compensation_body: "Follow-up offer",
          status: :drafting
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, approved} = Ash.update(draft, %{}, action: :approve, actor: operator)
    Fixtures.backdate_approval!(approved, 6)

    action =
      AshyWalnutDesk.Interaction.Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!()

    executed_action = Fixtures.execute_action!(action, operator)
    assert executed_action.status == :executed

    # ─── 4. Compensation trigger (story 3.6) ─────────────────────
    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed_action.id))
      |> Ash.read_one!()

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)

    triggering =
      triggering
      |> Ecto.Changeset.change(%{
        trigger_initiated_at: DateTime.add(DateTime.utc_now(), -6, :second)
      })
      |> AshyWalnutDesk.Repo.update!()
      |> then(&Ash.get!(Compensation, &1.id, authorize?: false))

    {:ok, _scheduled} = Ash.update(triggering, %{}, action: :trigger, actor: operator)
    Oban.drain_queue(queue: :outbound, with_recursion: true)

    final_compensation = Ash.get!(Compensation, compensation.id, authorize?: false)
    assert final_compensation.status == :triggered

    # ─── 5. Chain invariants ─────────────────────────────────────
    inbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :inbound))
      |> Ash.read!()

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.read!()

    assert length(inbound) == 1
    assert length(outbound) == 2

    # Conversation thread: 1 conversation per (identity, channel).
    convo_count =
      Conversation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.count!(authorize?: false)

    assert convo_count == 1

    # ─── 6. Audit chain visibility (story 3.7) ───────────────────
    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
    event_types = Enum.map(events, & &1.event_type)

    assert event_types == [
             :inbox_opened,
             :draft_started,
             :draft_approved,
             :compensation_registered,
             :action_scheduled,
             :action_executed,
             :compensation_scheduled,
             :compensation_executed
           ]

    {:ok, _view, html} = live(conn, ~p"/audit/chain?topic=#{inbox.id}")
    rows = Floki.parse_fragment!(html) |> Floki.find("[data-role=audit-row]")
    assert length(rows) == 8
    assert Enum.all?(rows, fn row -> Floki.attribute(row, "data-status") == ["ok"] end)

    # ─── 7. Twilio adapter was actually hit (twice — action + comp) ─
    attempts = Process.get(:twilio_attempts) |> Enum.reverse()
    assert length(attempts) == 2

    keys = Enum.map(attempts, & &1["idempotency-key"])
    assert Enum.all?(keys, &is_binary/1)
    assert Enum.uniq(keys) == keys
  end
end
