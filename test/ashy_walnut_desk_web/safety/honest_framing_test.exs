defmodule AshyWalnutDeskWeb.Safety.HonestFramingTest do
  use ExUnit.Case, async: true

  @scan_roots ["lib/ashy_walnut_desk_web", "priv/gettext"]
  @banned_terms ["unsend", "undo send", "recall message", "take back"]

  test "user-facing surfaces avoid banned unsend framing" do
    violations =
      @scan_roots
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*")))
      |> Enum.filter(&(File.regular?(&1) and !excluded_path?(&1)))
      |> Enum.flat_map(&find_violations_in_file/1)

    assert violations == [],
           "Banned framing terms found:\n" <>
             Enum.join(violations, "\n") <>
             "\nRewrite user-facing copy to preserve honest framing (no unsend semantics)."
  end

  defp excluded_path?(path) do
    String.contains?(path, "/test/") or String.contains?(path, "/specs/")
  end

  defp find_violations_in_file(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      downcased = String.downcase(line)

      @banned_terms
      |> Enum.filter(&String.contains?(downcased, &1))
      |> Enum.map(fn term ->
        "#{path}:#{line_no} contains banned framing term #{inspect(term)}: #{String.trim(line)}"
      end)
    end)
  end
end
