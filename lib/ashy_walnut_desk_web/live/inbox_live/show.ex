defmodule AshyWalnutDeskWeb.InboxLive.Show do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Interaction.{Action, Compensation, Draft, Inbox}
  alias AshyWalnutDeskWeb.Components.CountdownSendButton
  alias AshyWalnutDeskWeb.InboxLive.ChainComponent
  require Ash.Query

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load_inbox(id, socket.assigns.current_user, false) do
      {:ok, inbox} ->
        {:ok,
         socket
         |> assign(inbox: inbox, countdown_active?: false, seconds_left: 5)
         |> assign_draft_form()}

      {:error, _} ->
        {:ok,
         socket |> put_flash(:error, gettext("Inbox not found.")) |> push_navigate(to: ~p"/inbox")}
    end
  end

  @impl true
  def handle_event("validate_draft", %{"draft_form" => params}, socket) do
    {:noreply,
     assign(socket, draft_form: AshPhoenix.Form.validate(socket.assigns.draft_form, params))}
  end

  @impl true
  def handle_event("save_draft", %{"draft_form" => params}, socket) do
    params =
      if socket.assigns.inbox.draft == nil do
        params
        |> Map.put("inbox_id", socket.assigns.inbox.id)
        |> Map.put("status", "drafting")
      else
        params
      end

    case AshPhoenix.Form.submit(socket.assigns.draft_form, params: params) do
      {:ok, _draft} -> {:noreply, reload(socket)}
      {:error, form} -> {:noreply, assign(socket, draft_form: form)}
    end
  end

  @impl true
  def handle_event("approve_draft", _params, socket) do
    actor = socket.assigns.current_user

    with %Draft{} = draft <- socket.assigns.inbox.draft,
         true <- ready_for_approval?(draft),
         {:ok, _approved} <- Ash.update(draft, %{}, action: :approve, actor: actor),
         {:ok, action} <- find_action_for_draft(draft.id, actor) do
      Process.send_after(self(), {:countdown_tick, action.id, 4}, 1_000)
      Process.send_after(self(), {:execute_action, action.id}, 5_000)

      {:noreply,
       socket
       |> assign(countdown_active?: true, seconds_left: 5)
       |> reload()}
    else
      false -> {:noreply, put_flash(socket, :error, gettext("Draft is not ready for approval."))}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not approve draft."))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Draft is not ready for approval."))}
    end
  end

  @impl true
  def handle_info({:countdown_tick, action_id, seconds_left}, socket) do
    if current_action_id(socket) == action_id and seconds_left >= 0 and
         socket.assigns.countdown_active? do
      if seconds_left > 0 do
        Process.send_after(self(), {:countdown_tick, action_id, seconds_left - 1}, 1_000)
      end

      {:noreply, assign(socket, :seconds_left, seconds_left)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:execute_action, action_id}, socket) do
    actor = socket.assigns.current_user

    case Ash.get(Action, action_id, actor: actor) do
      {:ok, action} ->
        _ = Ash.update(action, %{}, action: :execute, actor: actor)

        {:noreply,
         socket
         |> assign(countdown_active?: false, seconds_left: 0)
         |> reload()}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(countdown_active?: false)
         |> put_flash(:error, gettext("Could not execute action."))}
    end
  end

  defp current_action_id(socket),
    do: socket.assigns.inbox.action && socket.assigns.inbox.action.id

  defp ready_for_approval?(draft) do
    draft.status == :drafting and String.trim(draft.body || "") != "" and
      String.trim(draft.compensation_body || "") != ""
  end

  defp reload(socket) do
    case load_inbox(socket.assigns.inbox.id, socket.assigns.current_user, true) do
      {:ok, inbox} -> socket |> assign(inbox: inbox) |> assign_draft_form()
      {:error, _} -> socket
    end
  end

  defp load_inbox(id, actor, allow_archived?) do
    opts = [actor: actor]

    with {:error, _} <- Ash.get(Inbox, id, opts),
         true <- allow_archived? and actor.role == :admin do
      Ash.get(Inbox, id, Keyword.put(opts, :action, :read_with_archived))
    else
      {:ok, inbox} -> {:ok, load_chain(inbox, actor)}
      {:error, _} = err -> err
      false -> {:error, :not_found}
    end
  end

  # F5/A1: thread the current_user actor through every chain-piece
  # load so a future tightening of any resource's `:read` policy
  # (e.g. dropping `:viewer` from `Draft.:read` per F8) is honored
  # by the LV automatically. Stages the actor isn't allowed to see
  # render as `nil` — the chain component already handles that.
  defp load_chain(inbox, actor) do
    inbox = Ash.load!(inbox, [:conversation], actor: actor)
    conversation = Ash.load!(inbox.conversation, [:identity], actor: actor)

    draft =
      Draft
      |> Ash.Query.filter(inbox_id == ^inbox.id)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.read_one!(actor: actor)

    action =
      if draft do
        case find_action_for_draft(draft.id, actor) do
          {:ok, found} -> found
          {:error, _} -> nil
        end
      end

    compensation =
      if action do
        Compensation
        |> Ash.Query.filter(action_id == ^action.id)
        |> Ash.read_one!(actor: actor)
      end

    inbox
    |> Map.put(:conversation, conversation)
    |> Map.put(:draft, draft)
    |> Map.put(:action, action)
    |> Map.put(:compensation, compensation)
  end

  # S6: single actor-aware lookup. Returns `{:ok, action}` or
  # `{:error, :not_found}`; callers decide whether nil-coalesce
  # (chain load) or pattern-match (approve flow). Replaces the
  # previous split between `find_action_for_draft/1` (authorize?:
  # false) and `find_action_for_draft!/2` — actor-aware shouldn't
  # differ in raise behaviour.
  defp find_action_for_draft(draft_id, actor) do
    Action
    |> Ash.Query.filter(draft_id == ^draft_id)
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, action} -> {:ok, action}
      other -> other
    end
  end

  defp assign_draft_form(socket) do
    actor = socket.assigns.current_user
    inbox = socket.assigns.inbox

    form =
      case inbox.draft do
        nil ->
          Draft
          |> AshPhoenix.Form.for_create(:compose_draft,
            actor: actor,
            as: "draft_form",
            params: %{"inbox_id" => inbox.id, "status" => :drafting}
          )

        %Draft{status: :drafting} = draft ->
          AshPhoenix.Form.for_update(draft, :revise, actor: actor, as: "draft_form")

        _ ->
          nil
      end

    assign(socket, draft_form: form && to_form(form))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-6 px-6 py-8">
      <.live_component module={ChainComponent} id="inbox-chain" inbox={@inbox} />

      <section class="rounded border border-zinc-200 p-4" data-role="conversation-context">
        <h2 class="text-base font-semibold text-zinc-900">{gettext("Conversation")}</h2>
        <p class="text-sm text-zinc-700">{@inbox.summary}</p>
        <p class="text-xs text-zinc-500">{to_string(@inbox.conversation.identity.display_name)}</p>
      </section>

      <section class="rounded border border-zinc-200 p-4" data-role="draft-section">
        <h2 class="text-base font-semibold text-zinc-900">{gettext("Draft")}</h2>

        <.simple_form
          :if={@draft_form}
          for={@draft_form}
          id="draft-form"
          phx-change="validate_draft"
          phx-submit="save_draft"
        >
          <.input field={@draft_form[:body]} type="textarea" label={gettext("Body")} required />
          <.input
            field={@draft_form[:compensation_body]}
            type="textarea"
            label={gettext("Compensation")}
          />
          <:actions>
            <.button type="submit" data-role="save-draft">{gettext("Save draft")}</.button>
          </:actions>
        </.simple_form>

        <p :if={@inbox.draft && @inbox.draft.status != :drafting} class="text-sm text-zinc-600">
          {gettext("Draft status")}: {to_string(@inbox.draft.status)}
        </p>

        <.live_component
          :if={@inbox.draft}
          module={CountdownSendButton}
          id="countdown-send"
          disabled={!ready_for_approval?(@inbox.draft)}
          countdown_active?={@countdown_active?}
          seconds_left={@seconds_left}
        />
      </section>
    </div>
    """
  end
end
