defmodule Mix.Tasks.Phase1.Demo.Seed do
  @shortdoc "Seed deterministic Phase 1 demo data for screenshot capture"

  @moduledoc """
  Seeds an admin user and an Identity with linked Event/Appointment/Note rows
  so `just screenshots` can drive the timeline UI deterministically.

  Idempotent: re-running adds another generation of records (the Playwright
  capture script keys on the most recently created identity by display name).

  ## Examples

      mix phase1.demo.seed
      mix phase1.demo.seed --email demo-admin@example.com --display-name "Aria Demo"
  """

  use Mix.Task

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Appointment
  alias AshyWalnutDesk.Identity.Event
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Note

  @switches [email: :string, display_name: :string]

  @impl Mix.Task
  def run(argv) do
    # The seed bypasses `User.:register`'s `forbid_if always()` policy and
    # auto-promotes to `:admin` via `authorize?: false` (intentional for
    # deterministic screenshot fixtures). That same shape is a
    # privilege-escalation path if invoked against a prod DB, so refuse
    # to run anywhere except dev/test.
    unless Mix.env() in [:dev, :test] do
      Mix.raise(
        "phase1.demo.seed is dev/test-only — it bypasses `User.:register` " <>
          "policy and auto-grants :admin. Refusing to run in Mix.env=" <>
          inspect(Mix.env()) <> "."
      )
    end

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    email = Keyword.get(opts, :email, "demo-admin@example.com")
    display_name = Keyword.get(opts, :display_name, "Aria Demo")

    Mix.Task.run("app.start")

    admin = ensure_admin(email)
    identity = create_identity(admin, display_name)
    seed_timeline(admin, identity)

    Mix.shell().info("""
    [phase1.demo.seed] OK
      admin email     : #{email}
      admin id        : #{admin.id}
      identity id     : #{identity.id}
      identity name   : #{display_name}
    """)
  end

  defp ensure_admin(email) do
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

  defp promote_if_needed(%User{role: :admin} = user), do: user

  defp promote_if_needed(%User{} = user) do
    user
    |> Ash.Changeset.for_update(:assign_role, %{role: :admin}, authorize?: false)
    |> Ash.update!()
  end

  defp create_identity(admin, display_name) do
    Identity
    |> Ash.Changeset.for_create(
      :register_identity,
      %{
        display_name: display_name,
        primary_identifier: "demo-#{Ash.UUID.generate()}",
        notes_summary: "Demo client for Phase 1 screenshot capture."
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp seed_timeline(admin, identity) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Event
    |> Ash.Changeset.for_create(
      :record_event,
      %{
        identity_id: identity.id,
        occurred_at: DateTime.add(now, -86_400, :second),
        summary: "Initial consultation",
        body: "Discussed background and goals. Plan: schedule follow-up next week."
      },
      actor: admin
    )
    |> Ash.create!()

    Appointment
    |> Ash.Changeset.for_create(
      :schedule_appointment,
      %{
        identity_id: identity.id,
        scheduled_for: DateTime.add(now, 7 * 86_400, :second),
        appointment_type: :initial,
        summary: "Follow-up appointment"
      },
      actor: admin
    )
    |> Ash.create!()

    Note
    |> Ash.Changeset.for_create(
      :record_note,
      %{
        identity_id: identity.id,
        body: "Prefers email contact. Confirmed mailing address on file."
      },
      actor: admin
    )
    |> Ash.create!()

    :ok
  end
end
