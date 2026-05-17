defmodule AshyWalnutDesk.Interaction.AdapterStubTest do
  use AshyWalnutDesk.DataCase, async: true

  alias AshyWalnutDesk.Interaction.Adapters.Stub

  test "stub adapter implements behaviour contract" do
    Code.ensure_loaded!(Stub)

    assert function_exported?(Stub, :channel_slug, 0)
    assert function_exported?(Stub, :send_outbound, 2)
    assert Stub.channel_slug() == "stub"
    assert {:ok, %{stub: true}} = Stub.send_outbound(%{}, %{})
  end
end
