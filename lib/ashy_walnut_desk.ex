defmodule AshyWalnutDesk do
  @moduledoc """
  AshyWalnutDesk keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @interaction_domain AshyWalnutDesk.Interaction

  def interaction_domain, do: @interaction_domain
end
