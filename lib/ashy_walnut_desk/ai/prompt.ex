defmodule AshyWalnutDesk.AI.Prompt do
  @moduledoc false

  @type system_block :: %{
          required(:type) => String.t(),
          required(:text) => String.t(),
          optional(:cache_control) => %{required(:type) => String.t()} | nil
        }

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t()
        }

  @type metadata :: map()

  @type t :: %__MODULE__{
          model: String.t() | nil,
          max_tokens: pos_integer() | nil,
          system_blocks: [system_block()],
          messages: [message()],
          metadata: metadata() | nil
        }

  defstruct [:model, :max_tokens, system_blocks: [], messages: [], metadata: %{}]
end
