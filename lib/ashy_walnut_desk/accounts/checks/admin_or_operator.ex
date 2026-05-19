defmodule AshyWalnutDesk.Accounts.Checks.AdminOrOperator do
  @moduledoc """
  Ash policy check that admits actors whose `:role` is either
  `:admin` or `:operator`.

  Replaces the two-line pair:

      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(actor_attribute_equals(:role, :operator))

  with a single `authorize_if(AshyWalnutDesk.Accounts.Checks.AdminOrOperator)`.

  The pair appears ~25× across Interaction-axis and Identity-axis
  resources (any operator-writable action). Extracting this lets a
  future role-system change happen in one file instead of touching
  every resource. See `specs/security/phase-3-hardening-summary.md`
  for the theme this check formalizes.

  Other role checks stay as explicit `actor_attribute_equals/2`
  calls — they're either admin-only (~30 sites, single line each)
  or admin+operator+viewer trio on `:read` (~11 sites). A separate
  trio helper would save fewer lines than this one and is not
  worth the abstraction.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "role in [:admin, :operator]"

  @impl true
  def match?(%{role: role}, _subject, _opts) when role in [:admin, :operator], do: true
  def match?(_actor, _subject, _opts), do: false
end
