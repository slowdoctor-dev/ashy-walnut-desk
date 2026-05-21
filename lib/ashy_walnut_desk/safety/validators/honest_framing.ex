defmodule AshyWalnutDesk.Safety.Validators.HonestFraming do
  @moduledoc false

  @behaviour AshyWalnutDesk.Safety.Validator

  alias AshyWalnutDesk.Safety.HonestFraming

  @locale_key "validator.violations.honest_framing"

  @impl true
  def check(text, _opts \\ []) when is_binary(text) do
    case HonestFraming.check(text) do
      :ok -> []
      {:error, _term} -> [violation()]
    end
  end

  defp violation do
    %{
      code: :honest_framing,
      severity: :error,
      span: nil,
      locale_key: @locale_key
    }
  end
end
