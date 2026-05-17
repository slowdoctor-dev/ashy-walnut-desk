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
end
