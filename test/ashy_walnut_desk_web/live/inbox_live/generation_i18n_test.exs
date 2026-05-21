defmodule AshyWalnutDeskWeb.InboxLive.GenerationI18nTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  defp sign_in_as(conn, role) do
    email = "inbox-i18n-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "generation and validation strings render as gettext-backed UI copy", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    {_operator_conn, operator} = sign_in_as(build_conn(), :operator)

    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    html = render(view)
    assert html =~ "Generation"
    assert html =~ "Candidates"
    assert html =~ "No drafting candidates yet."
  end
end
