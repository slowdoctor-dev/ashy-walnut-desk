defmodule AshyWalnutDeskWeb.Phase2E2ETest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Action,
    AuditChain,
    Channel,
    Compensation,
    Conversation,
    Draft,
    Inbox,
    Message
  }

  require Ash.Query

  describe "complete chain end-to-end" do
    test "new inbox -> draft -> approve/countdown -> executed", %{conn: conn} do
      {conn, operator} = sign_in_as(conn, :operator)
      {admin_conn, admin} = sign_in_as(build_conn(), :admin)
      _ = admin_conn

      {:ok, identity} =
        Ash.create(
          Identity,
          %{
            display_name: "Case #{System.unique_integer([:positive])}",
            primary_identifier: "+1555#{System.unique_integer([:positive])}"
          },
          action: :register_identity,
          actor: admin
        )

      {:ok, _channel} =
        Ash.create(
          Channel,
          %{
            slug: "stub",
            display_name: "Stub",
            adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
          },
          action: :register_channel,
          actor: admin
        )

      {:ok, new_view, _html} = live(conn, ~p"/inbox/new?identity_id=#{identity.id}")
      _ = render_click(element(new_view, "[data-role=create-inbox]"))

      inbox =
        Inbox
        |> Ash.Query.filter(summary == "Operator initiated")
        |> Ash.Query.sort(created_at: :desc)
        |> Ash.read_one!(authorize?: false)

      assert inbox.status == :open

      {:ok, show_view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

      _html =
        show_view
        |> form("#draft-form", %{
          "draft_form" => %{"body" => "Phase2 outbound", "compensation_body" => "Follow-up offer"}
        })
        |> render_submit()

      draft = Draft |> Ash.Query.filter(inbox_id == ^inbox.id) |> Ash.read_one!(authorize?: false)
      assert draft.status == :drafting

      _ = render_click(element(show_view, "[data-role=approve-draft]"))
      assert render(show_view) =~ "Sending in"

      :timer.sleep(5_500)

      draft = Draft |> Ash.Query.filter(inbox_id == ^inbox.id) |> Ash.read_one!(authorize?: false)

      action =
        Action
        |> Ash.Query.filter(draft_id == ^draft.id)
        |> Ash.read_one!(authorize?: false)

      compensation =
        Compensation
        |> Ash.Query.filter(action_id == ^action.id)
        |> Ash.read_one!(authorize?: false)

      conversation =
        Conversation
        |> Ash.Query.filter(id == ^inbox.conversation_id)
        |> Ash.read_one!(authorize?: false)

      message =
        Message
        |> Ash.Query.filter(conversation_id == ^conversation.id and direction == :outbound)
        |> Ash.Query.sort(created_at: :desc)
        |> Ash.read_one!(authorize?: false)

      inbox = Inbox |> Ash.Query.filter(id == ^inbox.id) |> Ash.read_one!(authorize?: false)

      assert action.status == :executed
      assert compensation.status == :registered
      assert message.approved_by_id == operator.id
      assert inbox.status == :executed

      assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
      assert length(events) == 5

      assert Enum.map(events, & &1.event_type) == [
               :inbox_opened,
               :draft_started,
               :draft_approved,
               :compensation_registered,
               :action_executed
             ]

      [first | rest] = events
      assert is_nil(first.prev_hash)

      Enum.reduce(rest, first.hash, fn event, prev_hash ->
        assert event.prev_hash == prev_hash
        event.hash
      end)
    end
  end

  describe "cross-link denied on soft-deleted Identity" do
    test "open_conversation rejects archived identity and writes no conversation rows" do
      admin = create_user(:admin)
      operator = create_user(:operator)

      {:ok, identity} =
        Ash.create(
          Identity,
          %{
            display_name: "Archived #{System.unique_integer([:positive])}",
            primary_identifier: "+1555#{System.unique_integer([:positive])}"
          },
          action: :register_identity,
          actor: admin
        )

      {:ok, archived_identity} = Ash.update(identity, %{}, action: :archive, actor: admin)

      {:ok, channel} =
        Ash.create(
          Channel,
          %{
            slug: "stub-#{System.unique_integer([:positive])}",
            display_name: "Stub",
            adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
          },
          action: :register_channel,
          actor: admin
        )

      subject = "archived-denial-#{System.unique_integer([:positive])}"

      assert {:error, _error} =
               Ash.create(
                 Conversation,
                 %{subject: subject, identity_id: archived_identity.id, channel_id: channel.id},
                 action: :open_conversation,
                 actor: operator
               )

      persisted =
        Conversation
        |> Ash.read!(action: :read_with_archived, authorize?: false)
        |> Enum.filter(&(&1.identity_id == archived_identity.id and &1.subject == subject))

      assert persisted == []
    end
  end

  defp sign_in_as(conn, role) do
    email = "phase2-e2e-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
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
