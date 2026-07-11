defmodule Mix.Tasks.Phase5.Demo.Seed do
  @shortdoc "Seed Phase 4/5 demo data for manuals + grounded-generation screenshots"

  @moduledoc """
  Seeds everything the Phase 4/5 screenshot tour needs:

  - Three Manuals: one revised twice (version history), one plain,
    one archived (archived-badge state on `/manuals`).
  - A Persona for generation.
  - Inbox A: an inbound question plus a **generated, validator-passed
    candidate grounded in the scheduling manual** — `InboxLive.Show`
    renders the generation panel with validator + retrieval badges.
  - Inbox B: the same generation driven through approve → countdown →
    executed, so `/audit/chain?topic=<B>` shows the 7-event chain
    including `draft_generation_*` with retrieval payload fields.

  Generation and indexing workers run synchronously in-process (the
  deterministic Fixture adapters — no network). Prints `KEY=value`
  lines consumed by `scripts/screenshots-phase5.sh`.

  ## Examples

      mix phase5.demo.seed
      mix phase5.demo.seed --email demo-admin@example.com
  """

  use Mix.Task

  alias AshyWalnutDesk.AI.Jobs.GenerationWorker
  alias AshyWalnutDesk.DemoSeedHelpers
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Action,
    Adapter,
    Channel,
    Conversation,
    Draft,
    Inbox,
    Message
  }

  alias AshyWalnutDesk.Knowledge.Jobs.ChunkAndEmbedWorker
  alias AshyWalnutDesk.Knowledge.{Manual, Persona}

  require Ash.Query

  @switches [email: :string]

  @impl Mix.Task
  def run(argv) do
    DemoSeedHelpers.guard_env!("phase5.demo.seed")

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    email = Keyword.get(opts, :email, "demo-admin@example.com")

    Mix.Task.run("app.start")

    admin = DemoSeedHelpers.ensure_admin(email)
    channel = ensure_channel(admin)
    persona = ensure_persona(admin)

    scheduling =
      ensure_manual(admin, "scheduling-playbook", "Scheduling playbook", scheduling_body())

    scheduling = maybe_revise(admin, scheduling)
    _billing = ensure_manual(admin, "billing-faq", "Billing FAQ", billing_body())
    _archived = ensure_archived_manual(admin)

    index_all_manuals!(admin)

    {inbox_a, _draft_a} = seed_grounded_candidate(admin, channel, persona, "Panel Demo")
    {inbox_b, _executed} = seed_executed_chain(admin, channel, persona, "Chain Demo")

    Mix.shell().info("""
    [phase5.demo.seed] OK
    MANUAL_ID=#{scheduling.id}
    INBOX_A=#{inbox_a.id}
    INBOX_B=#{inbox_b.id}
    """)
  end

  defp scheduling_body do
    """
    Appointment scheduling requests: always confirm the requested time
    with the client before promising a slot.

    If the requested time is unavailable, offer the two nearest
    alternatives and note the client's preference on the record.
    """
  end

  defp billing_body do
    "Billing questions: route disputes to the admin; never quote refunds in a draft."
  end

  defp ensure_channel(admin) do
    Channel
    |> Ash.Query.filter(slug == "stub-phase5")
    |> Ash.read_one!(actor: admin)
    |> case do
      %Channel{} = channel ->
        channel

      nil ->
        Ash.create!(
          Channel,
          %{
            slug: "stub-phase5",
            display_name: "Stub Phase 5",
            adapter_module: Adapter.stub_module_string(),
            enabled?: true
          },
          action: :register_channel,
          actor: admin
        )
    end
  end

  defp ensure_persona(admin) do
    Persona
    |> Ash.Query.filter(slug == "front-desk-default")
    |> Ash.read_one!(actor: admin)
    |> case do
      %Persona{} = persona ->
        persona

      nil ->
        Ash.create!(
          Persona,
          %{
            name: "Front-desk default",
            slug: "front-desk-default",
            system_prompt:
              "You draft concise, factual front-desk replies for operator review. " <>
                "Never promise outcomes; confirm details before committing to anything.",
            disclosure_text: "AI-assisted draft; reviewed by a human operator.",
            guardrail_notes: "No pricing quotes. No availability guarantees."
          },
          action: :create,
          actor: admin
        )
    end
  end

  defp ensure_manual(admin, slug, title, body) do
    Manual
    |> Ash.Query.filter(slug == ^slug)
    |> Ash.read_one!(actor: admin)
    |> case do
      %Manual{} = manual ->
        manual

      nil ->
        Ash.create!(Manual, %{title: title, slug: slug, body: body},
          action: :author,
          actor: admin
        )
    end
  end

  # Give the scheduling manual a second revision so the edit screen
  # shows real version history.
  defp maybe_revise(admin, %Manual{revision: 1} = manual) do
    Ash.update!(
      manual,
      %{body: manual.body <> "\nCancellations inside 24 hours go to the day sheet."},
      action: :revise,
      actor: admin
    )
  end

  defp maybe_revise(_admin, manual), do: manual

  defp ensure_archived_manual(admin) do
    manual = ensure_manual(admin, "legacy-notes", "Legacy notes", "Superseded onboarding notes.")

    case manual.status do
      :archived -> manual
      :active -> Ash.update!(manual, %{}, action: :archive, actor: admin)
    end
  end

  defp index_all_manuals!(admin) do
    Manual
    |> Ash.read!(action: :read_with_archived, actor: admin)
    |> Enum.each(fn manual ->
      :ok =
        ChunkAndEmbedWorker.perform(%Oban.Job{
          args: %{"manual_id" => manual.id, "revision" => manual.revision},
          attempt: 1,
          max_attempts: 3
        })
    end)
  end

  defp seed_grounded_candidate(admin, channel, persona, label) do
    inbox = seed_inbox_with_inbound(admin, channel, label)
    draft = generate!(admin, inbox, persona)
    {inbox, draft}
  end

  defp seed_executed_chain(admin, channel, persona, label) do
    inbox = seed_inbox_with_inbound(admin, channel, label)
    draft = generate!(admin, inbox, persona)

    approved =
      Ash.update!(
        draft,
        %{compensation_body: "If anything was unclear about the time, please reply here."},
        action: :approve,
        actor: admin
      )

    {:ok, _} = backdate_for_countdown(approved)
    action = action_for(approved.id)
    {:ok, executed} = drive_to_executed(action, admin)
    {inbox, executed}
  end

  defp seed_inbox_with_inbound(admin, channel, label) do
    suffix =
      :erlang.unique_integer([:positive])
      |> rem(1_000_000_000)
      |> Integer.to_string()
      |> String.pad_leading(9, "0")

    identity =
      Ash.create!(
        Identity,
        %{
          display_name: "#{label} Client",
          primary_identifier: "+1558#{suffix}",
          notes_summary: "Demo client for Phase 5 screenshot capture."
        },
        action: :register_identity,
        actor: admin
      )

    conversation =
      Ash.create!(
        Conversation,
        %{
          subject: "#{label} — grounded generation demo",
          identity_id: identity.id,
          channel_id: channel.id
        },
        action: :open_conversation,
        actor: admin
      )

    inbox =
      Ash.create!(
        Inbox,
        %{
          conversation_id: conversation.id,
          summary: "#{label}: client asks to confirm an appointment time."
        },
        action: :record_inbox,
        actor: admin
      )

    Ash.create!(
      Message,
      %{
        conversation_id: conversation.id,
        direction: :inbound,
        body: "Hi — can you confirm my appointment scheduling request for Friday 2pm?"
      },
      action: :record_message,
      authorize?: false,
      context: %{from_inbound_webhook: true}
    )

    inbox
  end

  defp generate!(admin, inbox, persona) do
    draft =
      Ash.create!(
        Draft,
        %{inbox_id: inbox.id, persona_id: persona.id},
        action: :generate,
        actor: admin
      )

    :ok =
      GenerationWorker.perform(%Oban.Job{
        args: %{"draft_id" => draft.id},
        attempt: 1,
        max_attempts: 3
      })

    Ash.get!(Draft, draft.id, authorize?: false)
  end

  # Same countdown backdate escape hatch as phase3.demo.seed.
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

  defp drive_to_executed(action, admin) do
    {:ok, scheduled} = Ash.update(action, %{}, action: :execute, actor: admin)

    stub_response = %{
      "provider" => "stub",
      "status" => "queued",
      "to" => "[scrubbed]",
      "simulated" => true
    }

    Ash.update(
      scheduled,
      %{adapter_response: stub_response},
      action: :complete_outbound,
      authorize?: false,
      context: %{from_action_worker: true}
    )
  end
end
