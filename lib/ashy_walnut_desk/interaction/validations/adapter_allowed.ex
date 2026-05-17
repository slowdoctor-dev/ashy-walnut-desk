defmodule AshyWalnutDesk.Interaction.Validations.AdapterAllowed do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    case adapter_module(changeset) do
      nil ->
        :ok

      adapter_module ->
        if allowed_adapter?(adapter_module) do
          :ok
        else
          {:error, field: :adapter_module, message: "is not in the configured adapter allowlist"}
        end
    end
  end

  defp adapter_module(changeset) do
    Changeset.get_attribute(changeset, :adapter_module) ||
      changeset.data.adapter_module
  end

  defp allowed_adapter?(adapter_module) when is_binary(adapter_module) do
    allowed =
      :ashy_walnut_desk
      |> Application.get_env(:channel_adapters, [])
      |> Enum.map(&Atom.to_string/1)
      |> MapSet.new()

    case module_string_from_input(adapter_module) do
      {:ok, module_string} -> MapSet.member?(allowed, module_string)
      :error -> false
    end
  end

  defp allowed_adapter?(_), do: false

  defp module_string_from_input("Elixir." <> _ = adapter_module) do
    case safe_existing_atom(adapter_module) do
      {:ok, module} -> {:ok, Atom.to_string(module)}
      :error -> :error
    end
  end

  defp module_string_from_input(adapter_module) do
    module_string = "Elixir." <> adapter_module

    case safe_existing_atom(module_string) do
      {:ok, module} -> {:ok, Atom.to_string(module)}
      :error -> :error
    end
  end

  defp safe_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end
end
