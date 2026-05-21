defmodule AshyWalnutDeskWeb.InboxLive.Components.ValidatorBadge do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:validator_state, validator_state(assigns.validator_output))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} data-role="validator-badge" class={badge_class(@validator_state.kind)}>
      <p class="text-xs font-semibold uppercase tracking-wide">
        {status_label(@validator_state.kind)}
      </p>

      <ul :if={@validator_state.kind == :failed} class="mt-2 list-disc pl-4 text-xs">
        <li :for={message <- @validator_state.messages}>{message}</li>
      </ul>
    </div>
    """
  end

  defp validator_state(%Ash.ForbiddenField{}), do: %{kind: :restricted, messages: []}

  defp validator_state(%{"passed?" => true}), do: %{kind: :passed, messages: []}

  defp validator_state(%{"passed?" => false, "violations" => violations})
       when is_list(violations) do
    %{kind: :failed, messages: Enum.map(violations, &violation_message/1)}
  end

  defp validator_state(%{"passed?" => false}),
    do: %{kind: :failed, messages: [gettext("Validation failed")]}

  defp validator_state(_), do: %{kind: :unknown, messages: []}

  defp status_label(:passed), do: gettext("Validation passed")
  defp status_label(:failed), do: gettext("Validation failed")
  defp status_label(:restricted), do: gettext("Validation restricted")
  defp status_label(:unknown), do: gettext("Validation pending")

  defp violation_message(%{"locale_key" => locale_key}) when is_binary(locale_key),
    do: locale_key_message(locale_key)

  defp violation_message(%{"code" => code}) when is_binary(code),
    do: locale_key_message("validator.violations." <> code)

  defp violation_message(%{code: code}) when is_atom(code),
    do: locale_key_message("validator.violations." <> Atom.to_string(code))

  defp violation_message(_), do: gettext("validator.violations.prohibited_phrase")

  # Keep locale keys as static gettext calls so gettext.extract sees them.
  defp locale_key_message("validator.violations.guarantee_claim"),
    do: gettext("validator.violations.guarantee_claim")

  defp locale_key_message("validator.violations.diagnostic_claim"),
    do: gettext("validator.violations.diagnostic_claim")

  defp locale_key_message("validator.violations.pricing_assertion"),
    do: gettext("validator.violations.pricing_assertion")

  defp locale_key_message("validator.violations.prohibited_phrase"),
    do: gettext("validator.violations.prohibited_phrase")

  defp locale_key_message("validator.violations.honest_framing"),
    do: gettext("validator.violations.honest_framing")

  defp locale_key_message("validator.violations.length_exceeded"),
    do: gettext("validator.violations.length_exceeded")

  defp locale_key_message(_), do: gettext("Validation failed")

  defp badge_class(:passed),
    do: "rounded border border-emerald-300 bg-emerald-50 p-2 text-emerald-900"

  defp badge_class(:failed),
    do: "rounded border border-red-300 bg-red-50 p-2 text-red-900"

  defp badge_class(:restricted),
    do: "rounded border border-zinc-300 bg-zinc-50 p-2 text-zinc-700"

  defp badge_class(:unknown),
    do: "rounded border border-zinc-300 bg-zinc-50 p-2 text-zinc-700"
end
