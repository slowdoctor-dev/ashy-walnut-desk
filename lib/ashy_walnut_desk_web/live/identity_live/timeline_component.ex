defmodule AshyWalnutDeskWeb.IdentityLive.TimelineComponent do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} data-role="timeline">
      <h2 class="text-base font-semibold text-zinc-800">{gettext("Timeline")}</h2>

      <ol :if={@entries != []} class="mt-4 space-y-3">
        <li
          :for={entry <- @entries}
          id={"timeline-#{entry.kind}-#{entry.id}"}
          data-kind={entry.kind}
          data-timestamp={DateTime.to_iso8601(entry.timestamp)}
          class="rounded border border-zinc-200 p-3"
        >
          <div class="flex items-center justify-between text-xs text-zinc-500">
            <span class="font-mono uppercase tracking-wide">{kind_label(entry.kind)}</span>
            <time datetime={DateTime.to_iso8601(entry.timestamp)}>
              {format_timestamp(entry.timestamp)}
            </time>
          </div>

          <p class="mt-1 text-sm text-zinc-800">{render_text(entry.summary)}</p>

          <p :if={entry.detail} class="mt-1 text-xs text-zinc-500">{render_text(entry.detail)}</p>
        </li>
      </ol>

      <p :if={@entries == []} class="mt-4 text-sm text-zinc-500" data-role="timeline-empty">
        {gettext("No linked records yet.")}
      </p>
    </section>
    """
  end

  defp kind_label(:event), do: gettext("Event")
  defp kind_label(:appointment), do: gettext("Appointment")
  defp kind_label(:note), do: gettext("Note")

  defp render_text(%Ash.ForbiddenField{}), do: gettext("[redacted]")
  defp render_text(nil), do: nil
  defp render_text(text), do: text
end
