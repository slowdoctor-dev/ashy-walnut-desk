defmodule AshyWalnutDesk.Interaction.ErrorHelpers do
  @moduledoc """
  Shared helpers for change/validation modules in the Interaction
  axis. Currently just `error_to_string/1`, used to coerce any
  error shape (exception, atom, term) into a printable string for
  changeset `error:` attributes and policy/validation messages.

  See S3 in the simplicity review — replaces three near-identical
  `defp error_text/1` copies across `CompensationAtApproval`,
  `CountdownGuard`, and `ExecuteOutbound`.
  """

  @doc """
  Coerce an error term into a printable string.

  - Exceptions → `Exception.message/1`
  - Anything else → `inspect/1`
  """
  @spec error_to_string(term()) :: String.t()
  def error_to_string(error) do
    if is_exception(error), do: Exception.message(error), else: inspect(error)
  end
end
