defmodule AshyWalnutDesk.AI.Response do
  @moduledoc false

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:cache_read_input_tokens) => non_neg_integer(),
          optional(:cache_creation_input_tokens) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          text: String.t(),
          usage: usage(),
          stop_reason: String.t() | nil,
          raw: map() | nil
        }

  defstruct [:text, :stop_reason, :raw, usage: %{}]
end
