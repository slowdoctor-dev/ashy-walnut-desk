defmodule AshyWalnutDesk.Knowledge.Embedders.FixtureTest do
  @moduledoc """
  Story 5.2 AC2 — the Fixture embedder is deterministic, offline,
  L2-normalized at the configured dimension, and ranks overlapping
  texts closer than disjoint ones under cosine similarity.
  """

  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Knowledge.Embedder
  alias AshyWalnutDesk.Knowledge.Embedders.Fixture

  defp cosine(a, b) do
    Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
  end

  test "deterministic across calls and dimension matches config" do
    {:ok, [v1]} = Fixture.embed(["confirm the appointment time"])
    {:ok, [v2]} = Fixture.embed(["confirm the appointment time"])

    assert v1 == v2
    assert length(v1) == Embedder.dimension()
    assert Enum.all?(v1, &is_float/1)
  end

  test "vectors are L2-normalized" do
    {:ok, [vector]} = Fixture.embed(["scheduling requests need confirmation"])

    norm = vector |> Enum.reduce(0.0, fn x, acc -> acc + x * x end) |> :math.sqrt()
    assert_in_delta norm, 1.0, 1.0e-9
  end

  test "overlapping texts rank closer than disjoint texts" do
    {:ok, [query, related, unrelated]} =
      Fixture.embed([
        "how do we handle appointment scheduling",
        "appointment scheduling is handled by confirming the requested time",
        "zebra volcano quantum umbrella"
      ])

    assert cosine(query, related) > cosine(query, unrelated)
  end

  test "token order does not change the vector (bag-of-words)" do
    {:ok, [a, b]} = Fixture.embed(["confirm appointment time", "time appointment confirm"])
    assert a == b
  end

  test "empty text yields a defined unit vector" do
    {:ok, [vector]} = Fixture.embed(["   "])
    assert [1.0 | rest] = vector
    assert Enum.all?(rest, &(&1 == 0.0))
  end

  test "honors an explicit :dimension option" do
    {:ok, [vector]} = Fixture.embed(["short"], dimension: 64)
    assert length(vector) == 64
  end
end
