defmodule AshyWalnutDeskWeb.InboxLive.New do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Inbox}

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, identity_id: Map.get(params, "identity_id"), error: nil)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    actor = socket.assigns.current_user

    with identity_id when not is_nil(identity_id) <- socket.assigns.identity_id,
         {:ok, channel} <- fetch_stub_channel(),
         {:ok, conversation} <-
           Ash.create(
             Conversation,
             %{
               subject: "Operator opened inbox",
               identity_id: identity_id,
               channel_id: channel.id
             },
             action: :open_conversation,
             actor: actor
           ),
         {:ok, inbox} <-
           Ash.create(
             Inbox,
             %{
               conversation_id: conversation.id,
               status: :open,
               summary: "Operator initiated",
               recorded_by_id: actor.id
             },
             action: :record_inbox,
             actor: actor
           ) do
      {:noreply, push_navigate(socket, to: ~p"/inbox/#{inbox.id}")}
    else
      nil -> {:noreply, assign(socket, :error, gettext("identity_id is required"))}
      {:error, _} -> {:noreply, assign(socket, :error, gettext("Could not create inbox chain."))}
    end
  end

  defp fetch_stub_channel do
    case Ash.read(Channel, action: :read, authorize?: false) do
      {:ok, channels} ->
        Enum.find(channels, &(&1.slug == "stub"))
        |> then(&if &1, do: {:ok, &1}, else: {:error, :missing_stub})

      error ->
        error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl space-y-6 px-6 py-8">
      <.header>{gettext("New inbox")}</.header>

      <p class="text-sm text-zinc-600">
        {gettext("Create conversation and inbox in one operator action.")}
      </p>
      <p :if={@identity_id} class="text-xs text-zinc-500">identity_id: {@identity_id}</p>
      <p :if={@error} class="text-sm text-rose-700" data-role="new-inbox-error">{@error}</p>

      <.button phx-click="create" data-role="create-inbox">{gettext("Create inbox")}</.button>
    </div>
    """
  end
end
