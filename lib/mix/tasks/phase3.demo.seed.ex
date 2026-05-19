defmodule Mix.Tasks.Phase3.Demo.Seed do
  @shortdoc "Seed Phase 3 chain data ready for AuditLive + compensation screenshots"

  @moduledoc """
  Seeds a full Phase 3 chain that's driven all the way through to
  `Action.:executed` so screenshots can show:

  - `AuditLive.Chain` topic list with at least one populated chain
  - `AuditLive.Chain` detail with the full 6-event sequence
    (inbox_opened → draft_started → draft_approved →
    compensation_registered → action_scheduled → action_executed)
  - `InboxLive.Show` with the compensation trigger affordance
    visible (parent Action is `:executed`, Compensation is
    `:registered`)

  The chain uses the Phase-2 stub adapter so no network call is
  attempted. The outbound message persists with `simulated: true`
  in the adapter response.

  ## Examples

      mix phase3.demo.seed
      mix phase3.demo.seed --email demo-admin@example.com --display-name "Aria Demo"
  """

  use Mix.Task

  alias AshyWalnutDesk.DemoSeedHelpers
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Action,
    Adapter,
    Channel,
    Conversation,
    Draft,
    Inbox
  }

  require Ash.Query

  @switches [email: :string, display_name: :string]

  @impl Mix.Task
  def run(argv) do
    DemoSeedHelpers.guard_env!("phase3.demo.seed")

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    email = Keyword.get(opts, :email, "demo-admin@example.com")
    display_name = Keyword.get(opts, :display_name, "Aria Demo")

    Mix.Task.run("app.start")

    admin = DemoSeedHelpers.ensure_admin(email)
    channel = ensure_stub_channel(admin)
    identity = create_identity(admin, display_name)
    conversation = create_conversation(admin, identity, channel)
    inbox = create_inbox(admin, conversation, display_name)
    inbox = mark_drafting(admin, inbox)
    draft = create_draft(admin, inbox)
    approved = approve_draft(admin, draft)
    {:ok, _backdated} = backdate_for_countdown(approved)
    action = action_for(approved.id)
    {:ok, executed} = drive_to_executed(action, admin)

    Mix.shell().info("""
    [phase3.demo.seed] OK
      admin email     : #{email}
      admin id        : #{admin.id}
      identity id     : #{identity.id}
      conversation id : #{conversation.id}
      inbox id        : #{inbox.id}
      action id       : #{executed.id} (status: #{executed.status})

    AuditLive.Chain topic: #{inbox.id}
    InboxLive.Show URL  : /inbox/#{inbox.id}
    """)
  end

  defp ensure_stub_channel(admin) do
    existing =
      Channel
      |> Ash.Query.filter(slug == "stub-phase3")
      |> Ash.read_one!(actor: admin)

    case existing do
      %Channel{} = c ->
        c

      nil ->
        Channel
        |> Ash.Changeset.for_create(
          :register_channel,
          %{
            slug: "stub-phase3",
            display_name: "Stub Phase 3",
            adapter_module: Adapter.stub_module_string(),
            enabled?: true
          },
          actor: admin
        )
        |> Ash.create!()
    end
  end

  defp create_identity(admin, display_name) do
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
        primary_identifier: "+1557#{suffix}",
        notes_summary: "Demo client for Phase 3 screenshot capture."
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
        subject: "Audit-chain demo thread",
        identity_id: identity.id,
        channel_id: channel.id
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp create_inbox(admin, conversation, display_name) do
    Inbox
    |> Ash.Changeset.for_create(
      :record_inbox,
      %{
        conversation_id: conversation.id,
        summary: "#{display_name} — phase 3 chain demo."
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
        body: "Thanks for reaching out. Our team will follow up shortly.",
        compensation_body: "If anything in the prior message was unclear, please reach out.",
        status: :drafting
      },
      actor: admin
    )
    |> Ash.create!()
  end

  defp approve_draft(admin, draft) do
    draft
    |> Ash.Changeset.for_update(:approve, %{}, actor: admin)
    |> Ash.update!()
  end

  # Phase 2's `CountdownGuard` rejects `:execute` calls less than 5s
  # after `approved_at`. Backdating via raw SQL is the fastest path
  # — the test fixture uses `:backdate_approval_for_tests` which is
  # forbidden by policy and meant for tests only.
  defp backdate_for_countdown(draft) do
    new_ts = DateTime.add(DateTime.utc_now(), -10, :second)

    {:ok, _} =
      AshyWalnutDesk.Repo.query(
        "UPDATE drafts SET approved_at = $1 WHERE id = $2",
        [new_ts, Ecto.UUID.dump!(draft.id)]
      )

    {:ok, draft}
  end

  defp action_for(draft_id) do
    Action
    |> Ash.Query.filter(draft_id == ^draft_id)
    |> Ash.read_one!(authorize?: false)
  end

  # `Action.:execute` schedules an Oban job. In dev/test we drive
  # the worker synchronously by calling `Action.:complete_outbound`
  # with the same stub-adapter response shape the worker would
  # have written. This produces the audit chain entries the screen
  # tour needs (:action_scheduled + :action_executed) without
  # waiting on Oban's poll interval.
  defp drive_to_executed(action, admin) do
    {:ok, scheduled} = Ash.update(action, %{}, action: :execute, actor: admin)

    stub_response = %{
      "provider" => "stub",
      "status" => "queued",
      "to" => "[scrubbed]",
      "simulated" => true
    }

    # `scheduled` carries `status: :scheduled` from the :execute
    # transition. `:complete_outbound` validates StatusTransition
    # from [:scheduled], so we MUST pass the scheduled struct
    # (not the original :pending one).
    Ash.update(
      scheduled,
      %{adapter_response: stub_response},
      action: :complete_outbound,
      authorize?: false,
      context: %{from_action_worker: true}
    )
  end
end
