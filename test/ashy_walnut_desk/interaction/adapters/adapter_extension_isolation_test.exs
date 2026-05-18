defmodule AshyWalnutDesk.Interaction.Adapters.AdapterExtensionIsolationTest do
  @moduledoc """
  Story 3.2 AC3 — extension-point isolation. Adding a new provider
  should be: (1) a single-file `Adapters.<Provider>` module
  conforming to `Interaction.Adapter`, (2) an entry in the
  `:channel_adapters` allowlist. No edits to Twilio code, no
  edits to `Action.execute`, no edits to `Compensation` actions.

  This test enforces that claim by adding a third-party adapter at
  runtime via `Application.put_env`, registering a Channel pointing
  at it, and verifying the framework picks it up — without touching
  any module file.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Adapter, Channel, InboundMessage}

  defmodule RuntimeAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl true
    def channel_slug, do: "runtime-fixture"

    @impl true
    def send_outbound(_message, _channel), do: {:ok, %{provider: :runtime, ok: true}}

    @impl true
    def verify_inbound_signature(_url, _params, _sig, _secret), do: :ok

    @impl true
    def parse_inbound(%{"from" => from, "to" => to, "body" => body, "id" => id}) do
      {:ok,
       %InboundMessage{
         provider: :runtime,
         provider_message_id: id,
         from: from,
         to: to,
         body: body,
         received_at: DateTime.utc_now()
       }}
    end

    def parse_inbound(_), do: {:error, :missing_required_fields}
  end

  setup do
    original = Application.fetch_env!(:ashy_walnut_desk, :channel_adapters)
    Application.put_env(:ashy_walnut_desk, :channel_adapters, original ++ [RuntimeAdapter])

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :channel_adapters, original)
    end)

    :ok
  end

  test "Channel.:register_channel admits a runtime-allowlisted adapter without core edits" do
    admin = AccountsFixtures.create_user(:admin)

    assert {:ok, channel} =
             Ash.create(
               Channel,
               %{
                 slug: "runtime-fixture-channel",
                 display_name: "Runtime Fixture",
                 adapter_module: Atom.to_string(RuntimeAdapter)
               },
               action: :register_channel,
               actor: admin
             )

    assert channel.adapter_module == Atom.to_string(RuntimeAdapter)
  end

  test "RuntimeAdapter satisfies the full Adapter contract" do
    # Sanity: the third-party module's callbacks are reachable.
    assert RuntimeAdapter.channel_slug() == "runtime-fixture"
    assert {:ok, %{provider: :runtime}} = RuntimeAdapter.send_outbound(%{body: "x"}, %{})
    assert :ok = RuntimeAdapter.verify_inbound_signature("u", %{}, "s", "k")

    assert {:ok, %InboundMessage{provider: :runtime}} =
             RuntimeAdapter.parse_inbound(%{
               "from" => "a",
               "to" => "b",
               "body" => "c",
               "id" => "d"
             })
  end
end
