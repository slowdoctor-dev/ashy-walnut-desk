defmodule AshyWalnutDesk.Safety.ValidatorResult do
  @moduledoc false

  @type violation :: %{
          code: atom(),
          severity: :error | :warning,
          span: {non_neg_integer(), non_neg_integer()} | nil,
          locale_key: String.t()
        }

  @type t :: %__MODULE__{
          passed?: boolean(),
          violations: [violation()],
          baseline_version: String.t(),
          deployment_version: String.t() | nil
        }

  defstruct [:passed?, :baseline_version, :deployment_version, violations: []]
end
