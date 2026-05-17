defmodule AshyWalnutDeskWeb.InboxLive.ShowTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, Channel, Compensation, Conversation, Draft, Inbox}
  require Ash.Query

  defp sign_in_as(conn, role) do
    email = "inbox-show-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "compose, revise, approve, countdown, execute", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    {admin_conn, admin} = sign_in_as(build_conn(), :admin)
    _ = admin_conn

    {:ok, identity} =
      Ash.create(Identity, %{display_name: "Case", primary_identifier: "+155503"},
        action: :register_identity,
        actor: admin
      )

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-3",
          display_name: "Stub 3",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "Need callback", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: operator
      )

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "Need callback"},
        action: :record_inbox,
        actor: operator
      )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    html =
      view
      |> form("#draft-form", %{
        "draft_form" => %{"body" => "First draft", "compensation_body" => "Offer follow-up"}
      })
      |> render_submit()

    assert html =~ "First draft"

    view |> element("[data-role=approve-draft]") |> render_click()

    assert render(view) =~ "Sending in"

    :timer.sleep(5500)

    action =
      Action
      |> Ash.Query.filter(draft_id in ^draft_ids_for_inbox(inbox.id))
      |> Ash.read_one!(authorize?: false)

    assert action.status == :executed

    draft = Draft |> Ash.Query.filter(inbox_id == ^inbox.id) |> Ash.read_one!(authorize?: false)

    compensation =
      Compensation
      |> Ash.Query.filter(action_id == ^action.id)
      |> Ash.read_one!(authorize?: false)

    assert draft.status == :approved
    assert compensation.status == :registered
  end

  defp draft_ids_for_inbox(inbox_id) do
    Draft
    |> Ash.Query.filter(inbox_id == ^inbox_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end
end
