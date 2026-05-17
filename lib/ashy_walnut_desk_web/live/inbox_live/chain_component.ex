defmodule AshyWalnutDeskWeb.InboxLive.ChainComponent do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} data-role="inbox-chain" class="rounded border border-zinc-200 p-4">
      <h2 class="text-base font-semibold text-zinc-900">{gettext("Chain status")}</h2>
      <p class="mt-1 text-sm text-zinc-600">
        {gettext("Four recorded stages keep each response traceable.")}
      </p>

      <ol class="mt-4 grid gap-3 md:grid-cols-4">
        <li :for={step <- steps(@inbox)} data-stage={step.key} class={step_class(step.active?)}>
          <p class="text-xs uppercase tracking-wide text-zinc-500">{step.label}</p>
          <p class="mt-1 text-sm text-zinc-800">{step.state}</p>
        </li>
      </ol>
    </section>
    """
  end

  defp steps(inbox) do
    draft = Map.get(inbox, :draft)
    action = Map.get(inbox, :action)
    compensation = Map.get(inbox, :compensation)

    [
      %{key: :inbox, label: gettext("Inbox"), state: to_string(inbox.status), active?: true},
      %{
        key: :draft,
        label: gettext("Draft"),
        state: if(draft, do: to_string(draft.status), else: gettext("pending")),
        active?: not is_nil(draft)
      },
      %{
        key: :action,
        label: gettext("Action"),
        state: if(action, do: to_string(action.status), else: gettext("pending")),
        active?: not is_nil(action)
      },
      %{
        key: :compensation,
        label: gettext("Compensation"),
        state: if(compensation, do: to_string(compensation.status), else: gettext("pending")),
        active?: not is_nil(compensation)
      }
    ]
  end

  defp step_class(true), do: "rounded border border-zinc-300 bg-zinc-50 p-3"
  defp step_class(false), do: "rounded border border-dashed border-zinc-200 p-3 opacity-70"
end
