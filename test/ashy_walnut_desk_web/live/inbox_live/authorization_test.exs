defmodule AshyWalnutDeskWeb.InboxLive.AuthorizationTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Inbox}

  defp sign_in_as(conn, role) do
    email = "inbox-auth-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "viewer cannot reach write actions", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    {_viewer_conn, viewer} = sign_in_as(build_conn(), :viewer)

    {:ok, identity} =
      Ash.create(Identity, %{display_name: "Lee", primary_identifier: "+155502"},
        action: :register_identity,
        actor: admin
      )

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-2",
          display_name: "Stub 2",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "Topic", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: admin
      )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(
               Inbox,
               %{
                 conversation_id: conversation.id,
                 status: :open,
                 summary: "Blocked",
                 recorded_by_id: viewer.id
               },
               action: :record_inbox,
               actor: viewer
             )

    assert conn.status != 403
  end
end
