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

  alias AshyWalnutDesk.DemoSeedHelpers
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Adapter, Channel, Conversation, Draft, Inbox}
  require Ash.Query

  @switches [email: :string, display_name: :string]

  @impl Mix.Task
  def run(argv) do
    DemoSeedHelpers.guard_env!("phase2.demo.seed")

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    email = Keyword.get(opts, :email, "demo-admin@example.com")
    display_name = Keyword.get(opts, :display_name, "Aria Demo")

    Mix.Task.run("app.start")

    admin = DemoSeedHelpers.ensure_admin(email)
    channel = ensure_stub_channel(admin)
    identity = create_identity(admin, display_name)
    conversation = create_conversation(admin, identity, channel)
    open_inbox = create_inbox(admin, conversation, display_name, "open")
    drafting_inbox = create_inbox(admin, conversation, display_name, "drafting")
    drafting_inbox = mark_drafting(admin, drafting_inbox)
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
            adapter_module: Adapter.stub_module_string(),
            enabled?: true
          },
          actor: admin
        )
        |> Ash.create!()
    end
  end

  defp create_identity(admin, display_name) do
    # `primary_identifier` must be E.164 (sec-fix R3). Generate a
    # +1556-prefixed number (different prefix from Phase 1's +1555
    # so the two demo runs don't collide on the unique-hash index).
    suffix =
      :erlang.unique_integer([:positive])
      |> rem(1_000_000_000)
      |> Integer.to_string()
      |> String.pad_leading(9, "0")

    Identity
    |> Ash.Changeset.for_create(
      :register_identity,
      %{
        display_name: display_name,
        primary_identifier: "+1556#{suffix}",
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

  # A2: `label` is just text embedded in the summary — it does not set
  # the actual `:status` attribute (that goes through `:record_inbox`
  # default + `:mark_drafting` below). The previous parameter name
  # `status` falsely suggested state was set at create time.
  defp create_inbox(admin, conversation, display_name, label) do
    Inbox
    |> Ash.Changeset.for_create(
      :record_inbox,
      %{
        conversation_id: conversation.id,
        summary: "#{display_name} requested a callback this week (#{label})."
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp mark_drafting(admin, inbox) do
    inbox
    |> Ash.Changeset.for_update(:mark_drafting, %{}, actor: admin)
    |> Ash.update!()
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
