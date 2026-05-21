defmodule AshyWalnutDesk.Safety.HonestFraming do
  @moduledoc false

  @banned_terms ["unsend", "undo send", "recall message", "take back"]

  @spec banned_terms() :: [String.t()]
  def banned_terms, do: @banned_terms

  @spec check(String.t()) :: :ok | {:error, String.t()}
  def check(text) when is_binary(text) do
    downcased = String.downcase(text)

    case Enum.find(@banned_terms, &String.contains?(downcased, &1)) do
      nil -> :ok
      term -> {:error, term}
    end
  end
end
