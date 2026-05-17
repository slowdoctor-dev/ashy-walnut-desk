defmodule AshyWalnutDeskWeb.InboxLive.IndexTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

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

    identity = Fixtures.seed_identity(admin, display_name: "Alex", primary_identifier: "+155501")
    channel = Fixtures.seed_channel(admin, slug: "stub", display_name: "Stub")
    conversation = Fixtures.seed_conversation(admin, identity, channel, subject: "Need update")
    inbox = Fixtures.seed_inbox(admin, conversation, summary: "Question from customer")

    {:ok, view, html} = live(conn, ~p"/inbox?status=open")

    assert html =~ "Inbox"
    assert html =~ "Question from customer"
    assert has_element?(view, "#inbox-#{inbox.id}")
  end
end
