defmodule AshyWalnutDesk.Knowledge.EmbedderConformanceTest do
  @moduledoc """
  Story 5.2 AC1 — both embedder implementations satisfy the shared
  `Knowledge.Embedder` contract: batch in → same-length ordered batch
  out, numeric vectors of uniform dimension, `{:ok, []}` for `[]`.
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.Knowledge.Embedders.{Fixture, Voyage}

  setup do
    prev = Application.get_env(:ashy_walnut_desk, :voyage_req_options, [])

    Application.put_env(:ashy_walnut_desk, :voyage_req_options,
      plug: fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        inputs = Jason.decode!(raw)["input"]

        data =
          inputs
          |> Enum.with_index()
          |> Enum.map(fn {_text, index} ->
            %{"embedding" => [index * 1.0, 1.0], "index" => index}
          end)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => data}))
      end
    )

    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :voyage_req_options, prev) end)
    :ok
  end

  for module <- [Fixture, Voyage] do
    @module module

    test "#{inspect(module)} conforms to the Embedder contract" do
      assert {:ok, vectors} = @module.embed(["alpha beta", "gamma delta", "epsilon"])
      assert length(vectors) == 3

      assert Enum.all?(vectors, &is_list/1)
      assert Enum.all?(vectors, fn vector -> Enum.all?(vector, &is_number/1) end)

      assert [dimension] = vectors |> Enum.map(&length/1) |> Enum.uniq()
      assert dimension > 0

      assert {:ok, []} = @module.embed([])
    end

    test "#{inspect(module)} implements the behaviour" do
      behaviours =
        @module.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert AshyWalnutDesk.Knowledge.Embedder in behaviours
    end
  end
end
