defmodule AshyWalnutDesk.Accounts.SystemActor do
  @moduledoc """
  Idempotent provisioning + lookup of the inbound-webhook system
  actor (ADR-024). A singleton `User{role: :system}` row that the
  Twilio webhook controller authenticates as when creating
  `Inbox`, `Conversation`, and inbound `Message` rows.

  Created at app boot via `AshyWalnutDesk.Application.start/2`'s
  hook. Locked down by `Accounts.Changes.RegistrationGate` (which
  rejects sign-in attempts for any `system+%` email) and by the
  `Interaction.Checks.FromInboundWebhook` policy check (which gates
  every action this actor is allowed to invoke).

  A separate test asserts the system actor cannot drive
  `Draft.:approve`, `Action.:execute`, `Compensation.:trigger`, or
  any other send-path action.
  """

  alias AshyWalnutDesk.Accounts.User
  require Ash.Query

  @email "system+inbound@ashy-walnut-desk.local"

  @doc """
  Idempotent. Returns the system actor User struct, creating one
  if missing. Safe to call from `Application.start/2` and from
  tests in `setup`.
  """
  @spec ensure!() :: User.t()
  def ensure! do
    case lookup() do
      {:ok, %User{} = user} -> user
      :missing -> create!()
    end
  end

  @doc "The system actor's email constant — exported for test assertions."
  @spec email() :: String.t()
  def email, do: @email

  defp lookup do
    User
    |> Ash.Query.filter(email == ^@email)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %User{} = u} -> {:ok, u}
      {:ok, nil} -> :missing
      {:error, _} -> :missing
    end
  end

  defp create! do
    {:ok, user} =
      Ash.create(
        User,
        %{email: @email, role: :system},
        action: :register,
        authorize?: false
      )

    user
  end
end
