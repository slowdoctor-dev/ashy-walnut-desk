defmodule AshyWalnutDesk.Interaction.ChannelAllowlistTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.Channel

  defp create_admin do
    {:ok, admin} =
      Ash.create(
        User,
        %{email: "admin-#{System.unique_integer([:positive])}@example.com", role: :admin},
        action: :register,
        authorize?: false
      )

    admin
  end

  test "register_channel rejects adapter module outside configured allowlist" do
    admin = create_admin()
    unique = System.unique_integer([:positive])

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Ash.create(
               Channel,
               %{
                 slug: "blocked-#{unique}",
                 display_name: "Blocked #{unique}",
                 adapter_module: "Elixir.System"
               },
               action: :register_channel,
               actor: admin
             )

    assert Enum.any?(errors, fn error ->
             error.field == :adapter_module and
               String.contains?(error.message, "allowlist")
           end)
  end

  test "enable rejects non-allowlisted adapter module updates" do
    admin = create_admin()
    unique = System.unique_integer([:positive])

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Ash.update(
               channel,
               %{adapter_module: "Elixir.System"},
               action: :enable,
               actor: admin
             )

    assert Enum.any?(errors, fn error ->
             error.field == :adapter_module and
               String.contains?(error.message, "allowlist")
           end)
  end

  # Test-fix R5: `:enable` accepts `:adapter_module` in its accept
  # list. Two behaviours worth pinning:
  #
  # 1. Re-enable WITHOUT providing adapter_module → existing
  #    adapter is preserved (the common case for a temporary
  #    disable+re-enable to flush a vendor incident).
  # 2. Re-enable WITH a DIFFERENT on-allowlist adapter → the swap
  #    succeeds. This is intentional — it's how an admin migrates
  #    a channel from one provider to another. The unique slug
  #    stays; the adapter binding changes.
  #
  # Locking both with tests so a future tightening of `:enable`
  # (e.g. forbidding adapter swap on a non-archived channel) is
  # a deliberate decision rather than silent drift.

  test "enable without adapter_module preserves the existing adapter" do
    admin = create_admin()
    unique = System.unique_integer([:positive])
    original = "AshyWalnutDesk.Interaction.Adapters.Stub"

    {:ok, channel} =
      Ash.create(
        Channel,
        %{slug: "stub-#{unique}", display_name: "S", adapter_module: original},
        action: :register_channel,
        actor: admin
      )

    {:ok, _disabled} = Ash.update(channel, %{}, action: :disable, actor: admin)

    {:ok, reenabled} = Ash.update(channel, %{}, action: :enable, actor: admin)

    assert reenabled.adapter_module == original
    assert reenabled.enabled? == true
  end

  test "enable with a DIFFERENT on-allowlist adapter swaps it (intentional design)" do
    admin = create_admin()
    unique = System.unique_integer([:positive])

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "S",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, _disabled} = Ash.update(channel, %{}, action: :disable, actor: admin)

    {:ok, swapped} =
      Ash.update(
        channel,
        %{adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio"},
        action: :enable,
        actor: admin
      )

    assert swapped.adapter_module == "AshyWalnutDesk.Interaction.Adapters.Twilio"
    assert swapped.enabled? == true
  end
end
