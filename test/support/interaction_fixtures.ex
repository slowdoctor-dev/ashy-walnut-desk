defmodule AshyWalnutDesk.InteractionFixtures do
  @moduledoc """
  Shared Interaction-axis test fixtures. Replaces ~600 lines of
  duplicated `seed_*` / `create_*` helpers that lived inline in 14+
  test files. Each phase change to a resource shape (e.g.
  `Inbox.:record_inbox` dropping `:status` / `:recorded_by_id` in
  PR #37, the `:edit_draft` → `:revise` rename, the `:registration`
  gate in #38) used to require an N-file cascade — now a single
  helper edit.

  All fixtures bypass the production policy / actor flow only where
  necessary. Where actor-scoping is needed (channel registration is
  admin-only, etc.), the caller passes their own actor — fixtures
  don't silently authorize.

  See S1 in the simplicity review. Edge-case helpers (e.g. concurrency
  tests, custom seed shapes) stay inline pending TO-12 (Pass B
  follow-up at Phase 3 boundary).
  """

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Action,
    Adapter,
    Channel,
    Conversation,
    Draft,
    Inbox
  }

  @doc """
  Register a fresh Identity with the given admin actor. Returns the
  identity. `display_name` defaults to a unique generated value;
  pass `display_name: "..."` to override.
  """
  def seed_identity(admin, opts \\ []) do
    unique = System.unique_integer([:positive])
    display_name = Keyword.get(opts, :display_name, "Identity #{unique}")
    primary_identifier = Keyword.get(opts, :primary_identifier, "+1555#{unique}")

    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: display_name, primary_identifier: primary_identifier},
        action: :register_identity,
        actor: admin
      )

    identity
  end

  @doc """
  Register a fresh stub channel. Uses
  `Interaction.Adapter.stub_module_string/0` so the adapter name
  isn't hardcoded in 21+ places (A1).
  """
  def seed_channel(admin, opts \\ []) do
    unique = System.unique_integer([:positive])
    slug = Keyword.get(opts, :slug, "stub-#{unique}")
    display_name = Keyword.get(opts, :display_name, "Stub #{unique}")
    adapter_module = Keyword.get(opts, :adapter_module, Adapter.stub_module_string())

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: slug,
          display_name: display_name,
          adapter_module: adapter_module
        },
        action: :register_channel,
        actor: admin
      )

    channel
  end

  @doc """
  Open a conversation between an identity and a channel.
  """
  def seed_conversation(actor, identity, channel, opts \\ []) do
    subject = Keyword.get(opts, :subject, "Thread")

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: subject, identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: actor
      )

    conversation
  end

  @doc """
  Record a fresh Inbox for a conversation. `status` is forced to
  `:open` by the action (PR #37); pass through `:mark_drafting`
  separately if a `:drafting` inbox is needed.
  """
  def seed_inbox(actor, conversation, opts \\ []) do
    summary = Keyword.get(opts, :summary, "Need response")

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: summary},
        action: :record_inbox,
        actor: actor
      )

    inbox
  end

  @doc """
  Compose a fresh Draft against an inbox.
  """
  def seed_draft(actor, inbox, opts \\ []) do
    attrs =
      Map.merge(
        %{
          inbox_id: inbox.id,
          body: "Draft body",
          compensation_body: "Compensate",
          status: :drafting
        },
        Map.new(Keyword.take(opts, [:body, :compensation_body, :status]))
      )

    {:ok, draft} = Ash.create(Draft, attrs, action: :compose_draft, actor: actor)
    draft
  end

  @doc """
  Build the full Identity → Channel → Conversation → Inbox → Draft →
  approve chain in one call. Optionally pass a pre-built admin to
  reuse (most callers want to set this up once in `setup` and reuse,
  because the `users_one_admin_idx` partial unique constraint
  forbids multiple admins per transaction).

  Returns a map with every fixture in the chain:

      %{
        admin:        %User{},
        operator:     %User{},
        identity:     %Identity{},
        channel:      %Channel{},
        conversation: %Conversation{},
        inbox:        %Inbox{},
        draft:        %Draft{},  # status: :approved after the :approve call
        action:       %Action{}
      }

  Note: this does NOT execute the action (that's the countdown-elapsed
  path). Use `backdate_approval!/2` then `Ash.update(action, %{}, action:
  :execute, actor: operator)` to drive a complete chain.
  """
  def seed_approved_chain(opts \\ []) do
    admin = Keyword.get_lazy(opts, :admin, fn -> AccountsFixtures.create_user(:admin) end)

    operator =
      Keyword.get_lazy(opts, :operator, fn -> AccountsFixtures.create_user(:operator) end)

    identity = seed_identity(admin)

    channel_opts = Keyword.take(opts, [:adapter_module, :slug, :display_name])
    channel = Keyword.get_lazy(opts, :channel, fn -> seed_channel(admin, channel_opts) end)
    conversation = seed_conversation(operator, identity, channel)
    inbox = seed_inbox(operator, conversation)
    draft = seed_draft(operator, inbox)

    {:ok, approved} = Ash.update(draft, %{}, action: :approve, actor: operator)

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!(authorize?: false)

    %{
      admin: admin,
      operator: operator,
      identity: identity,
      channel: channel,
      conversation: conversation,
      inbox: inbox,
      draft: approved,
      action: action
    }
  end

  @doc """
  Backdate the draft's `approved_at` timestamp via the test-only
  `:backdate_approval_for_tests` action (forbidden by policy; bypassed
  with `authorize?: false`). Used by countdown tests to skip past
  the 5-second send window without sleeping. Returns the updated
  draft.
  """
  def backdate_approval!(draft, seconds \\ 10) do
    Ash.update!(
      draft,
      %{approved_at: DateTime.add(DateTime.utc_now(), -seconds, :second)},
      action: :backdate_approval_for_tests,
      authorize?: false
    )
  end

  @doc """
  Story 3.5: `Action.:execute` enqueues an Oban job (`Jobs.OutboundSend`)
  per ADR-023. Tests that want the synchronous Phase 2 behavior call
  this helper:

  1. `Ash.update(action, %{}, action: :execute, actor: operator)`
     — flips status `:pending → :scheduled` and inserts the job.
  2. `Oban.drain_queue(queue: :outbound, with_recursion: true, with_safety: false)`
     — runs the worker in the calling process (Oban `testing: :manual`).
  3. Reloads the Action so callers see the final `:executed | :failed`
     status.

  Pass `:expect_failure` to skip the drain failure-loud option (worker
  raises only on bugs, not on adapter `{:error, _}` results — those
  surface on the Action row, not the job).
  """
  def execute_action!(action, actor, opts \\ []) do
    expect_failure? = Keyword.get(opts, :expect_failure, false)

    {:ok, scheduled} = Ash.update(action, %{}, action: :execute, actor: actor)

    Oban.drain_queue(
      queue: :outbound,
      with_recursion: true,
      with_safety: expect_failure?
    )

    Ash.get!(AshyWalnutDesk.Interaction.Action, scheduled.id, authorize?: false)
  end
end
