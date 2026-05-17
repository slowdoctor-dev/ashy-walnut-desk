defmodule Mix.Tasks.Phase2.Demo.Seed do
  @shortdoc "Seed deterministic Phase 2 inbox data for screenshot capture"

  @moduledoc """
  Seeds an admin user plus one Identity/Conversation/Inbox chain in `:open`
  so `just phase2-screenshots` can drive the InboxLive flow deterministically.

  ## Examples

      mix phase2.demo.seed
      mix phase2.demo.seed --email demo-admin@example.com --display-name "Aria Demo"
  """

  use Mix.Task

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Draft, Inbox}
  require Ash.Query

  @switches [email: :string, display_name: :string]

  @impl Mix.Task
  def run(argv) do
    unless Mix.env() in [:dev, :test] do
      Mix.raise(
        "phase2.demo.seed is dev/test-only — it bypasses `User.:register` " <>
          "policy and auto-grants :admin. Refusing to run in Mix.env=" <>
          inspect(Mix.env()) <> "."
      )
    end

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    email = Keyword.get(opts, :email, "demo-admin@example.com")
    display_name = Keyword.get(opts, :display_name, "Aria Demo")

    Mix.Task.run("app.start")

    admin = ensure_admin(email)
    channel = ensure_stub_channel(admin)
    identity = create_identity(admin, display_name)
    conversation = create_conversation(admin, identity, channel)
    open_inbox = create_inbox(admin, conversation, display_name, :open)
    drafting_inbox = create_inbox(admin, conversation, display_name, :drafting)
    _draft = create_draft(admin, drafting_inbox)

    Mix.shell().info("""
    [phase2.demo.seed] OK
      admin email     : #{email}
      admin id        : #{admin.id}
      identity id     : #{identity.id}
      conversation id : #{conversation.id}
      open inbox id   : #{open_inbox.id}
      drafting inbox id: #{drafting_inbox.id}
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

  defp ensure_stub_channel(admin) do
    existing =
      Channel
      |> Ash.Query.filter(slug == "stub-phase2")
      |> Ash.read_one!(actor: admin)

    case existing do
      %Channel{} = channel ->
        channel

      nil ->
        Channel
        |> Ash.Changeset.for_create(
          :register_channel,
          %{
            slug: "stub-phase2",
            display_name: "Stub Phase 2",
            adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub",
            enabled?: true
          },
          actor: admin
        )
        |> Ash.create!()
    end
  end

  defp create_identity(admin, display_name) do
    Identity
    |> Ash.Changeset.for_create(
      :register_identity,
      %{
        display_name: display_name,
        primary_identifier: "phase2-demo-#{Ash.UUID.generate()}",
        notes_summary: "Demo client for Phase 2 screenshot capture."
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp create_conversation(admin, identity, channel) do
    Conversation
    |> Ash.Changeset.for_create(
      :open_conversation,
      %{
        subject: "Need callback about schedule",
        identity_id: identity.id,
        channel_id: channel.id
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp create_inbox(admin, conversation, display_name, status) do
    Inbox
    |> Ash.Changeset.for_create(
      :record_inbox,
      %{
        conversation_id: conversation.id,
        status: status,
        summary: "#{display_name} requested a callback this week (#{status}).",
        recorded_by_id: admin.id
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp create_draft(admin, inbox) do
    Draft
    |> Ash.Changeset.for_create(
      :compose_draft,
      %{
        inbox_id: inbox.id,
        body: "Thanks for reaching out. We can call you tomorrow afternoon.",
        compensation_body:
          "If we miss the callback window, we will provide priority follow-up scheduling.",
        status: :drafting
      },
      actor: admin
    )
    |> Ash.create!()
  end
end
