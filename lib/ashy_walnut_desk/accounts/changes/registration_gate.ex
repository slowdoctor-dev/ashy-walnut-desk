defmodule AshyWalnutDesk.Accounts.Changes.RegistrationGate do
  @moduledoc """
  Runtime gate on the magic-link self-registration path. Hooked into
  `Accounts.User.:sign_in_with_magic_link` (which is also the
  registration path — the action `upsert`s by email). Existing users
  always pass through; new emails are admitted only when the
  `:registration_enabled?` application env is `true`.

  This is layered on top of the AshAuthentication strategy's own
  `registration_enabled?(true)` DSL flag. We keep the DSL `true` so
  the library still routes the request, but reject at change time
  when the deployer hasn't explicitly enabled registration. That
  way the framework default is "registration off," and deployers
  flip the env (`AWD_REGISTRATION_ENABLED=1`) once their allowlist /
  invite flow / SSO replacement is in place.

  Registration off → unknown email gets a generic
  `"registration is disabled"` error, returned through the normal
  AshAuthentication channel. Known emails proceed (sign-in for
  existing users isn't gated).

  See F1 in `/tmp/phase2-security-review.md`.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Accounts.User

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      cond do
        Enum.any?(changeset.errors) -> changeset
        system_actor_email?(changeset) -> reject_system(changeset)
        registration_enabled?() -> changeset
        existing_user?(changeset) -> changeset
        true -> reject(changeset)
      end
    end)
  end

  # ADR-024: the `system+inbound@<host>` actor created by
  # `Accounts.ensure_system_actor/0` must NEVER be reachable via
  # magic-link sign-in. Reject the magic-link path for any address
  # in the `system+` namespace regardless of the registration gate.
  defp system_actor_email?(changeset) do
    case Changeset.get_attribute(changeset, :email) do
      nil -> false
      email -> email |> to_string() |> String.downcase() |> String.starts_with?("system+")
    end
  end

  defp reject_system(changeset) do
    Changeset.add_error(changeset,
      field: :email,
      message: "system addresses cannot sign in via magic link"
    )
  end

  defp registration_enabled? do
    Application.get_env(:ashy_walnut_desk, :registration_enabled?, false) == true
  end

  defp existing_user?(changeset) do
    case Changeset.get_attribute(changeset, :email) do
      nil ->
        false

      email ->
        User
        |> Ash.Query.filter(email == ^email)
        |> Ash.exists(authorize?: false)
        |> case do
          {:ok, true} -> true
          _ -> false
        end
    end
  end

  defp reject(changeset) do
    Changeset.add_error(changeset,
      field: :email,
      message: "registration is disabled"
    )
  end
end
