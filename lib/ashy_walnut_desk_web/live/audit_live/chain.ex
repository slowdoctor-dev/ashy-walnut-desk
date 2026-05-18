defmodule AshyWalnutDeskWeb.AuditLive.Chain do
  @moduledoc """
  Admin-only viewer for the hash-chained `AuditEvent` log (story 3.7,
  resolves TO-14).

  - URL: `/audit/chain` — list distinct chain topics.
  - URL: `/audit/chain?topic=<inbox-uuid>` — show events for that
    chain topic, sorted ascending, with per-row hash-continuity
    status badges that mirror `mix audit.verify`'s exit semantics
    (`:ok` rows match their computed hash; `:broken` rows do not).

  Read-only. No mutation actions. Gated by
  `LiveUserAuth.:admin_required`.

  See `specs/phase-3/architecture.md §4`.
  """

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Interaction.AuditChain

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}
  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :admin_required}

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, topic: nil, events: [], topics: [], page: 1)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    topic = params["topic"]
    page = parse_page(params["page"])

    socket =
      socket
      |> assign(topic: topic, page: page)
      |> load_view()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_by_topic", %{"topic" => topic}, socket) do
    {:noreply, push_patch(socket, to: ~p"/audit/chain?topic=#{topic}")}
  end

  @impl true
  def handle_event("clear_topic", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/audit/chain")}
  end

  defp parse_page(nil), do: 1
  defp parse_page(""), do: 1

  defp parse_page(str) do
    case Integer.parse(str) do
      {n, ""} when n >= 1 -> n
      _ -> 1
    end
  end

  defp load_view(%{assigns: %{topic: nil}} = socket) do
    assign(socket, topics: AuditChain.all_chain_topics(), events: [])
  end

  defp load_view(%{assigns: %{topic: topic, page: page}} = socket) do
    all_rows = AuditChain.walk_with_status(topic)
    total = length(all_rows)

    offset = (page - 1) * @page_size
    page_rows = Enum.slice(all_rows, offset, @page_size)

    assign(socket,
      events: page_rows,
      total: total,
      topics: AuditChain.all_chain_topics()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl space-y-6 px-6 py-8">
      <header class="flex items-center justify-between">
        <h1 class="text-xl font-semibold text-zinc-900">{gettext("Audit chain")}</h1>
        <p class="text-xs text-zinc-500">
          {gettext("Admin only — read-only viewer")}
        </p>
      </header>

      <section :if={!@topic} class="rounded border border-zinc-200 p-4" data-role="topic-list">
        <h2 class="text-base font-semibold">{gettext("Chain topics")}</h2>

        <p :if={@topics == []} class="text-sm text-zinc-600">
          {gettext("No chain topics yet.")}
        </p>

        <ul :if={@topics != []} class="mt-2 divide-y divide-zinc-100">
          <li :for={topic <- @topics} class="flex items-center justify-between py-2">
            <code class="text-xs text-zinc-700">{topic}</code>
            <.link
              navigate={~p"/audit/chain?topic=#{topic}"}
              class="text-xs font-medium text-blue-700 hover:underline"
              data-role="open-topic"
            >
              {gettext("Open")} →
            </.link>
          </li>
        </ul>
      </section>

      <section :if={@topic} class="rounded border border-zinc-200 p-4" data-role="chain-events">
        <div class="mb-3 flex items-center justify-between">
          <div>
            <h2 class="text-base font-semibold">
              {gettext("Topic")}: <code class="font-mono text-sm">{@topic}</code>
            </h2>
            <p class="text-xs text-zinc-500">
              {gettext("%{count} events", count: assigns[:total] || 0)}
            </p>
          </div>

          <button
            type="button"
            phx-click="clear_topic"
            data-role="clear-topic"
            class="text-xs font-medium text-blue-700 hover:underline"
          >
            ← {gettext("All topics")}
          </button>
        </div>

        <table class="w-full text-xs">
          <thead class="text-left text-zinc-500">
            <tr>
              <th class="py-2 pr-3">{gettext("Status")}</th>
              <th class="py-2 pr-3">{gettext("Event")}</th>
              <th class="py-2 pr-3">{gettext("Subject")}</th>
              <th class="py-2 pr-3">{gettext("At")}</th>
              <th class="py-2">{gettext("Hash")}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{event, status} <- @events}
              data-role="audit-row"
              data-status={status}
              class={status_row_class(status)}
            >
              <td class="py-1 pr-3" data-role="status-badge">
                {status_label(status)}
              </td>
              <td class="py-1 pr-3 font-mono">{event.event_type}</td>
              <td class="py-1 pr-3 font-mono">
                {event.subject_kind}:{shorten(event.subject_id)}
              </td>
              <td class="py-1 pr-3 font-mono text-zinc-500">
                {NaiveDateTime.to_iso8601(event.inserted_at)}
              </td>
              <td class="py-1 font-mono text-zinc-500">{shorten(event.hash)}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  defp status_label(:ok), do: "✓ ok"
  defp status_label(:broken), do: "✗ broken"

  defp status_row_class(:ok), do: "border-b border-zinc-50"
  defp status_row_class(:broken), do: "border-b border-red-200 bg-red-50 text-red-900"

  defp shorten(nil), do: ""
  defp shorten(str) when is_binary(str), do: String.slice(str, 0, 12)
  defp shorten(other), do: to_string(other) |> String.slice(0, 12)
end
