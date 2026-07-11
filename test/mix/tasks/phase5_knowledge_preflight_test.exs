defmodule Mix.Tasks.Phase5.Knowledge.PreflightTest do
  @moduledoc """
  Story 5.7 AC1 — `mix phase5.knowledge.preflight` fails fast on
  non-allowlisted embedders, dimension mismatches, and a missing
  provider key; supports `--skip-network`; healthy configs pass in
  both the external-embedder and none postures. Voyage HTTP is stubbed
  at the Req plug boundary.
  """

  use AshyWalnutDesk.DataCase, async: false

  import ExUnit.CaptureIO

  @app_keys ~w(embedding_adapter embedding_adapter_allowlist embedding_model
               embedding_model_allowlist embedding_dimension voyage voyage_req_options)a

  setup do
    original_key = System.get_env("VOYAGE_API_KEY")
    originals = Map.new(@app_keys, fn k -> {k, Application.fetch_env(:ashy_walnut_desk, k)} end)

    on_exit(fn ->
      if is_nil(original_key),
        do: System.delete_env("VOYAGE_API_KEY"),
        else: System.put_env("VOYAGE_API_KEY", original_key)

      Enum.each(originals, fn
        {k, {:ok, v}} -> Application.put_env(:ashy_walnut_desk, k, v)
        {k, :error} -> Application.delete_env(:ashy_walnut_desk, k)
      end)
    end)

    System.delete_env("VOYAGE_API_KEY")
    Application.delete_env(:ashy_walnut_desk, :voyage)
    :ok
  end

  defp run_preflight(argv) do
    Mix.Task.reenable("phase5.knowledge.preflight")
    Mix.Task.run("phase5.knowledge.preflight", argv)
  end

  test "default test config (Fixture embedder) passes offline" do
    captured = capture_io(fn -> run_preflight(["--skip-network"]) end)
    assert captured =~ "✓ phase5.knowledge.preflight ok (network check skipped)"
  end

  test "none posture passes and reports lexical-only, even in network mode" do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, nil)

    captured = capture_io(fn -> run_preflight([]) end)
    assert captured =~ "lexical-only posture"
  end

  test "non-allowlisted embedder fails" do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, NotAReal.Embedder)

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/phase5.knowledge.preflight: 1 check\(s\) failed/, fn ->
          run_preflight(["--skip-network"])
        end
      end)

    assert captured =~ "not in :embedding_adapter_allowlist"
  end

  test "dimension drift against the column and the model fails" do
    Application.put_env(:ashy_walnut_desk, :embedding_dimension, 512)

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/2 check\(s\) failed/, fn ->
          run_preflight(["--skip-network"])
        end
      end)

    assert captured =~ "does not match the manual_chunks.embedding column dimension 1024"
    assert captured =~ "produces 1024-dimensional vectors"
  end

  test "Voyage without a key fails; with key + healthy provider passes" do
    Application.put_env(
      :ashy_walnut_desk,
      :embedding_adapter,
      AshyWalnutDesk.Knowledge.Embedders.Voyage
    )

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> run_preflight(["--skip-network"]) end
      end)

    assert captured =~ "VOYAGE_API_KEY is missing"

    System.put_env("VOYAGE_API_KEY", "dev-only-preflight-key")

    Application.put_env(:ashy_walnut_desk, :voyage_req_options,
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"data" => [%{"embedding" => [0.1], "index" => 0}]})
        )
      end
    )

    captured = capture_io(fn -> run_preflight([]) end)
    assert captured =~ "✓ phase5.knowledge.preflight ok (embedding provider reachable)"
  end

  test "Voyage provider rejecting the key fails with actionable hint" do
    Application.put_env(
      :ashy_walnut_desk,
      :embedding_adapter,
      AshyWalnutDesk.Knowledge.Embedders.Voyage
    )

    System.put_env("VOYAGE_API_KEY", "dev-only-revoked-key")

    Application.put_env(:ashy_walnut_desk, :voyage_req_options,
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"detail" => "unauthorized"}))
      end
    )

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/1 check\(s\) failed/, fn -> run_preflight([]) end
      end)

    assert captured =~ "embedding health check failed"
    assert captured =~ "verify VOYAGE_API_KEY validity/permissions"
  end
end
