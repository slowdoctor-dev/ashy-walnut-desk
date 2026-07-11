defmodule AshyWalnutDesk.Knowledge.EmbedderConfigTest do
  @moduledoc """
  Story 5.2 AC4 — configured defaults and allowlist-enforced adapter
  resolution, including the `:not_configured` posture
  (`EMBEDDING_ADAPTER=none`).
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.Knowledge.Embedder
  alias AshyWalnutDesk.Knowledge.Embedders.Fixture

  setup do
    prev = Application.fetch_env(:ashy_walnut_desk, :embedding_adapter)

    on_exit(fn ->
      case prev do
        {:ok, value} -> Application.put_env(:ashy_walnut_desk, :embedding_adapter, value)
        :error -> Application.delete_env(:ashy_walnut_desk, :embedding_adapter)
      end
    end)

    :ok
  end

  test "framework defaults: Fixture adapter, voyage model family, 1024 dimension" do
    assert Application.get_env(:ashy_walnut_desk, :embedding_adapter) == Fixture

    allowlist = Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist)
    assert Fixture in allowlist
    assert AshyWalnutDesk.Knowledge.Embedders.Voyage in allowlist

    model = Application.get_env(:ashy_walnut_desk, :embedding_model)
    assert model in Application.get_env(:ashy_walnut_desk, :embedding_model_allowlist)

    assert Embedder.dimension() == 1024
  end

  test "resolve/0 returns the configured allowlisted adapter" do
    assert {:ok, Fixture} = Embedder.resolve()
  end

  test "resolve/0 rejects a non-allowlisted module" do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, NotAReal.Embedder)
    assert {:error, {:embedder_not_allowed, NotAReal.Embedder}} = Embedder.resolve()
  end

  test "resolve/0 reports :not_configured when the adapter is nil (none posture)" do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, nil)
    assert {:error, :not_configured} = Embedder.resolve()
  end
end
