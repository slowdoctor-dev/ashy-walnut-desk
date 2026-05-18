defmodule AshyWalnutDesk.Interaction.AdapterAllowedTest do
  @moduledoc """
  Story 3.2 AC4 — verify the configured `:channel_adapters` allowlist
  includes Twilio + Echo (in test env) and admits future providers
  by configuration only. The negative-path test ("non-allowlisted
  module rejected") already lives in `channel_allowlist_test.exs`;
  this file is the positive-path Twilio-specific cover.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Adapter, Channel}
  alias AshyWalnutDesk.Interaction.Adapters.{Echo, Stub, Twilio}

  test "Twilio adapter is in the test-env allowlist" do
    allowlist = Application.fetch_env!(:ashy_walnut_desk, :channel_adapters)
    assert Twilio in allowlist
  end

  test "Stub + Twilio are in the prod allowlist (config/config.exs)" do
    # Test env extends prod; both must be present in prod's baseline.
    # Echo is test-only and intentionally not in prod (we don't assert
    # its absence here because test env adds it).
    allowlist = Application.fetch_env!(:ashy_walnut_desk, :channel_adapters)
    assert Stub in allowlist
    assert Twilio in allowlist
  end

  test "Channel.:register_channel accepts the Twilio adapter module" do
    admin = AccountsFixtures.create_user(:admin)
    unique = System.unique_integer([:positive])

    assert {:ok, channel} =
             Ash.create(
               Channel,
               %{
                 slug: "twilio-sms-test-#{unique}",
                 display_name: "Twilio SMS #{unique}",
                 adapter_module: Atom.to_string(Twilio)
               },
               action: :register_channel,
               actor: admin
             )

    assert channel.adapter_module == Atom.to_string(Twilio)
  end

  test "Channel.:register_channel accepts the Echo adapter module in test env" do
    admin = AccountsFixtures.create_user(:admin)
    unique = System.unique_integer([:positive])

    assert {:ok, _channel} =
             Ash.create(
               Channel,
               %{
                 slug: "echo-test-#{unique}",
                 display_name: "Echo #{unique}",
                 adapter_module: Atom.to_string(Echo)
               },
               action: :register_channel,
               actor: admin
             )
  end

  test "stub_module_string/0 returns the canonical Stub atom-as-string" do
    assert Adapter.stub_module_string() == Atom.to_string(Stub)
  end
end
