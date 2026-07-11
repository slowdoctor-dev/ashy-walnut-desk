defmodule AshyWalnutDesk.Knowledge.Embedders.VoyageTest do
  @moduledoc """
  Story 5.2 AC3 — request envelope, response ordering, error-class
  mapping, and ≤128 batching. HTTP stubbed at the Req plug boundary
  (`:voyage_req_options`); no network calls.
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.Knowledge.Embedders.Voyage

  setup do
    prev = Application.get_env(:ashy_walnut_desk, :voyage_req_options, [])
    prev_key = Application.get_env(:ashy_walnut_desk, :voyage)
    Application.put_env(:ashy_walnut_desk, :voyage, api_key: "test-voyage-key")

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :voyage_req_options, prev)

      case prev_key do
        nil -> Application.delete_env(:ashy_walnut_desk, :voyage)
        val -> Application.put_env(:ashy_walnut_desk, :voyage, val)
      end
    end)

    :ok
  end

  defp stub_with(fun) do
    Application.put_env(:ashy_walnut_desk, :voyage_req_options, plug: fun)
  end

  defp respond(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp success_body(vectors) do
    %{
      "object" => "list",
      "data" =>
        vectors
        |> Enum.with_index()
        |> Enum.map(fn {vector, index} -> %{"embedding" => vector, "index" => index} end),
      "model" => "voyage-3.5-lite",
      "usage" => %{"total_tokens" => 12}
    }
  end

  test "request carries bearer auth, model, input, and default input_type" do
    test_pid = self()

    stub_with(fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:captured, Map.new(conn.req_headers), Jason.decode!(raw)})
      respond(conn, 200, success_body([[0.1, 0.2]]))
    end)

    assert {:ok, [[0.1, 0.2]]} = Voyage.embed(["hello"])

    assert_received {:captured, headers, body}
    assert headers["authorization"] == "Bearer test-voyage-key"
    assert body["model"] == "voyage-3.5-lite"
    assert body["input"] == ["hello"]
    assert body["input_type"] == "document"
  end

  test "input_type option flows through (query embeddings at retrieval time)" do
    test_pid = self()

    stub_with(fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:captured, Jason.decode!(raw)})
      respond(conn, 200, success_body([[0.3]]))
    end)

    assert {:ok, [[0.3]]} = Voyage.embed(["what is the policy"], input_type: "query")
    assert_received {:captured, body}
    assert body["input_type"] == "query"
  end

  test "response vectors are re-ordered by index" do
    stub_with(fn conn ->
      respond(conn, 200, %{
        "data" => [
          %{"embedding" => [2.0], "index" => 1},
          %{"embedding" => [1.0], "index" => 0}
        ]
      })
    end)

    assert {:ok, [[1.0], [2.0]]} = Voyage.embed(["a", "b"])
  end

  test "batches over 128 inputs split into sequential requests" do
    test_pid = self()

    stub_with(fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      batch = Jason.decode!(raw)["input"]
      send(test_pid, {:batch, length(batch)})
      respond(conn, 200, success_body(Enum.map(batch, fn _ -> [1.0] end)))
    end)

    texts = Enum.map(1..130, &"text #{&1}")
    assert {:ok, vectors} = Voyage.embed(texts)
    assert length(vectors) == 130

    assert_received {:batch, 128}
    assert_received {:batch, 2}
  end

  test "model outside the allowlist is rejected before any network call" do
    stub_with(fn _conn -> flunk("no HTTP call expected for a disallowed model") end)

    assert {:error, {:model_not_allowed, "voyage-imaginary"}} =
             Voyage.embed(["x"], model: "voyage-imaginary")
  end

  test "empty input embeds to an empty list without HTTP" do
    stub_with(fn _conn -> flunk("no HTTP call expected for empty input") end)
    assert {:ok, []} = Voyage.embed([])
  end

  test "error classes: 429 / 5xx / 400 / 401" do
    for {status, expected} <- [
          {429, :rate_limited},
          {503, :transient},
          {400, :permanent},
          {401, :permanent}
        ] do
      stub_with(fn conn -> respond(conn, status, %{"detail" => "err"}) end)
      assert {:error, ^expected} = Voyage.embed(["x"])
    end
  end

  test "transport timeout maps to :timeout; other transport errors to :transient" do
    stub_with(fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, :timeout} = Voyage.embed(["x"])

    stub_with(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, :transient} = Voyage.embed(["x"])
  end
end
