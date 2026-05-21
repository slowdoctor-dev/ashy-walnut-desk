defmodule AshyWalnutDeskWeb.InboxLive.Components.GenerationPanel do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_component

  alias AshyWalnutDesk.Interaction.Draft
  alias AshyWalnutDeskWeb.InboxLive.Components.ValidatorBadge

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="rounded border border-zinc-200 p-4" data-role="generation-panel">
      <h2 class="text-base font-semibold text-zinc-900">{gettext("Generation")}</h2>
      <p class="text-sm text-zinc-700">
        {gettext("Generate candidate drafts under a selected persona.")}
      </p>

      <form id="generation-form" phx-submit="generate_draft" class="mt-3 flex items-end gap-3">
        <div class="flex-1">
          <label for="persona-select" class="mb-1 block text-sm font-medium text-zinc-800">
            {gettext("Persona")}
          </label>
          <select
            id="persona-select"
            name="generation_form[persona_id]"
            class="w-full rounded border border-zinc-300 px-2 py-2"
          >
            <option :for={persona <- @personas} value={persona.id}>
              {persona.name}
            </option>
          </select>
        </div>

        <.button type="submit" data-role="generate-draft" disabled={Enum.empty?(@personas)}>
          {gettext("Generate")}
        </.button>
      </form>

      <p :if={@generating?} class="mt-3 text-sm text-zinc-600" data-role="generation-spinner">
        {gettext("Generating draft…")}
      </p>

      <section class="mt-4 space-y-3" data-role="candidate-carousel">
        <h3 class="text-sm font-semibold text-zinc-900">{gettext("Candidates")}</h3>

        <p :if={Enum.empty?(@candidates)} class="text-sm text-zinc-600">
          {gettext("No drafting candidates yet.")}
        </p>

        <article
          :for={candidate <- @candidates}
          id={"candidate-#{candidate.id}"}
          data-role="candidate-card"
          class="rounded border border-zinc-200 p-3"
        >
          <div class="flex items-center justify-between gap-3">
            <p class="text-xs text-zinc-600">
              {gettext("Status")}: {to_string(candidate.status)}
            </p>

            <.live_component
              module={ValidatorBadge}
              id={"validator-badge-#{candidate.id}"}
              validator_output={candidate.ai_validator_output}
            />
          </div>

          <p class="mt-3 whitespace-pre-wrap text-sm text-zinc-800" data-role="candidate-body-preview">
            {candidate_preview(candidate)}
          </p>

          <div class="mt-3 flex gap-2">
            <.button
              type="button"
              phx-click="approve_candidate"
              phx-value-draft_id={candidate.id}
              data-role={"approve-candidate-#{candidate.id}"}
              disabled={!candidate_approvable?(candidate)}
            >
              {gettext("Approve")}
            </.button>

            <.button
              type="button"
              phx-click="reject_candidate"
              phx-value-draft_id={candidate.id}
              data-role={"reject-candidate-#{candidate.id}"}
            >
              {gettext("Reject")}
            </.button>

            <.button
              type="button"
              phx-click="regenerate_candidate"
              phx-value-draft_id={candidate.id}
              phx-value-persona_id={candidate.persona_id}
              data-role={"regenerate-candidate-#{candidate.id}"}
            >
              {gettext("Regenerate")}
            </.button>
          </div>
        </article>
      </section>
    </section>
    """
  end

  defp candidate_approvable?(%Draft{status: :drafting, ai_validator_output: %{"passed?" => true}}),
    do: true

  defp candidate_approvable?(_), do: false

  defp candidate_preview(%Draft{status: :generating}), do: gettext("Draft is generating.")

  defp candidate_preview(%Draft{body: body}) when is_binary(body) do
    body
    |> String.trim()
    |> case do
      "" -> gettext("Draft body is empty.")
      text -> String.slice(text, 0, 280)
    end
  end

  defp candidate_preview(_), do: gettext("Draft body is unavailable.")
end
