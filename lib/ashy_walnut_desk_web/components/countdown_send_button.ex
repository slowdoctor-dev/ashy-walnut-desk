defmodule AshyWalnutDeskWeb.Components.CountdownSendButton do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-3" data-role="countdown-send-button">
      <button
        type="button"
        phx-click="approve_draft"
        disabled={@disabled || @countdown_active?}
        class="rounded bg-zinc-900 px-3 py-2 text-sm font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-60"
        data-role="approve-draft"
      >
        <%= if @countdown_active? do %>
          {gettext("Sending in %{seconds}s…", seconds: @seconds_left)}
        <% else %>
          {gettext("Approve & send")}
        <% end %>
      </button>

      <p :if={@countdown_active?} class="text-xs text-zinc-600" data-role="countdown-hint">
        {gettext("Countdown is running on the server.")}
      </p>
    </div>
    """
  end
end
