defmodule AshyWalnutDeskWeb.InboxLive.IndexTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Inbox}

  defp sign_in_as(conn, role) do
    email = "inbox-index-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "operator sees inbox progression rows", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)

    {:ok, identity} =
      Ash.create(Identity, %{display_name: "Alex", primary_identifier: "+155501"},
        action: :register_identity,
        actor: admin
      )

    {:ok, channel} =
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

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "Need update", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: admin
      )

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "Question from customer"},
        action: :record_inbox,
        actor: admin
      )

    {:ok, view, html} = live(conn, ~p"/inbox?status=open")

    assert html =~ "Inbox"
    assert html =~ "Question from customer"
    assert has_element?(view, "#inbox-#{inbox.id}")
  end
end
