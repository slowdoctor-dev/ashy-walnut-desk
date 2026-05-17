defmodule AshyWalnutDesk.DemoSeedHelpers do
  @moduledoc """
  Shared building blocks for the per-phase `mix <phase>.demo.seed`
  tasks. Dev/test-only: each task that uses these helpers MUST first
  refuse to run outside `Mix.env() in [:dev, :test]` (see
  `guard_env!/1`), because the helpers themselves bypass `:register`
  policy + auto-promote to `:admin` via `authorize?: false`.

  Extracts the ~40 lines of duplicated `ensure_admin/1` +
  `promote_if_needed/1` that Phase 1 and Phase 2 demo seeds carry
  verbatim. Subsequent phases call into this module instead of
  copying the pattern again.

  See S2 in the simplicity review.
  """

  alias AshyWalnutDesk.Accounts.User

  @doc """
  Refuses to continue outside `Mix.env() in [:dev, :test]`. Call at
  the top of every demo-seed task's `run/1`. The error message
  includes the task name so the operator-on-prod sees what they hit.
  """
  @spec guard_env!(String.t()) :: :ok
  def guard_env!(task_name) do
    if Mix.env() in [:dev, :test] do
      :ok
    else
      Mix.raise(
        "#{task_name} is dev/test-only — it bypasses `User.:register` " <>
          "policy and auto-grants :admin. Refusing to run in Mix.env=" <>
          inspect(Mix.env()) <> "."
      )
    end
  end

  @doc """
  Idempotently fetch-or-create a `User` with the given email and
  promote them to `:admin`. Returns the live User struct.

  Bypasses `:register` policy (`authorize?: false`) — the gate is
  the caller's `guard_env!/1` invocation above.
  """
  @spec ensure_admin(String.t()) :: User.t()
  def ensure_admin(email) when is_binary(email) do
    case Ash.read_one(User, action: :get_by_email, arguments: %{email: email}, authorize?: false) do
      {:ok, %User{} = user} ->
        promote_if_needed(user)

      _ ->
        User
        |> Ash.Changeset.for_create(:register, %{email: email}, authorize?: false)
        |> Ash.create!()
        |> promote_if_needed()
    end
  end

  @doc """
  Force the user's role to `:admin` via `:assign_role`. No-op if
  already `:admin`. Always uses `authorize?: false`.
  """
  @spec promote_if_needed(User.t()) :: User.t()
  def promote_if_needed(%User{role: :admin} = user), do: user

  def promote_if_needed(%User{} = user) do
    user
    |> Ash.Changeset.for_update(:assign_role, %{role: :admin}, authorize?: false)
    |> Ash.update!()
  end
end
