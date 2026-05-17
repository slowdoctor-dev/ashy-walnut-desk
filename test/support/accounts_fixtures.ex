defmodule AshyWalnutDesk.AccountsFixtures do
  @moduledoc """
  Shared accounts-axis test fixtures. Bypasses production policies
  (`User.:register` is forbid-if-always; `:assign_role` is admin-only)
  via `authorize?: false` because tests need deterministic user shapes.

  Test-only — `lib/` code must never depend on this module. See S1
  in the simplicity review.

  ## DB-level constraints to be aware of

  The `users_one_admin_idx` partial unique index allows only ONE
  `:admin` row per Postgres transaction. Property tests and other
  callers that `setup`-mint an admin once and reuse it across
  iterations / cases are the working pattern. Calling
  `create_user(:admin)` twice inside a single transaction raises.
  """

  alias AshyWalnutDesk.Accounts.User

  @doc """
  Create a fresh user with the given role. Email uses a monotonic
  unique integer so callers can mint many in one test without
  collisions.

  Roles: `:admin`, `:operator`, `:viewer`. Defaults to `:operator`.
  """
  @spec create_user(:admin | :operator | :viewer) :: User.t()
  def create_user(role \\ :operator) when role in [:admin, :operator, :viewer] do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Ash.create(
        User,
        %{email: "#{role}-#{unique}@example.com", role: role},
        action: :register,
        authorize?: false
      )

    user
  end
end
