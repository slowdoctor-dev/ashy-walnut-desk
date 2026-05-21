defmodule AshyWalnutDesk.AI.Adapter do
  @moduledoc """
  Provider-agnostic generation boundary used by Phase 4 AI workflows.
  """

  alias AshyWalnutDesk.AI.{Prompt, Response}

  @callback complete(prompt :: Prompt.t(), opts :: keyword()) ::
              {:ok, Response.t()}
              | {:error,
                 :transient | :permanent | :rate_limited | :content_blocked | :timeout | term()}
end
