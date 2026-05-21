defmodule AshyWalnutDesk.Safety.Validator do
  @moduledoc false

  alias AshyWalnutDesk.Safety.ValidatorResult

  @callback check(text :: String.t(), opts :: keyword()) :: ValidatorResult.t()
end
