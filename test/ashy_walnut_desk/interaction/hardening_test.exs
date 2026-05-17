defmodule AshyWalnutDesk.Interaction.HardeningTest do
  @moduledoc """
  Regression tests for the Phase 2 implementation hardening pass.
  Each test pins a specific bypass that was open after the original
  Phase 2 implementation merged and was closed by this PR.

  Findings indexed by their R1/R2 review ID; see PR description.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Action,
    Channel,
    Compensation,
    Conversation,
    Draft,
    Inbox,
    Message
  }

  describe "S1: Draft.:revise cannot stamp approval fields" do
    test "rejects :approved_at and :approved_by_id as inputs (countdown bypass)" do
      %{operator: operator, draft: draft} = seed_drafting_chain()

      assert {:error, %Ash.Error.Invalid{} = error} =
               Ash.update(draft, %{approved_at: DateTime.utc_now()},
                 action: :revise,
                 actor: operator
               )

      assert Enum.any?(
               error.errors,
               &match?(%Ash.Error.Invalid.NoSuchInput{input: :approved_at}, &1)
             )

      assert {:error, %Ash.Error.Invalid{} = error2} =
               Ash.update(draft, %{approved_by_id: operator.id},
                 action: :revise,
                 actor: operator
               )

      assert Enum.any?(
               error2.errors,
               &match?(%Ash.Error.Invalid.NoSuchInput{input: :approved_by_id}, &1)
             )
    end
  end

  describe "S2/R2-3: register_pending + register are internal-only" do
    test "operator cannot create Action.:register_pending directly" do
      %{operator: operator, draft: draft, channel: channel} = seed_drafting_chain()

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 Action,
                 %{draft_id: draft.id, channel_id: channel.id},
                 action: :register_pending,
                 actor: operator
               )
    end

    test "operator cannot create Compensation.:register directly" do
      %{operator: operator, draft: draft, channel: channel} = seed_drafting_chain()

      {:ok, action} =
        Ash.create(
          Action,
          %{draft_id: draft.id, channel_id: channel.id},
          action: :register_pending,
          authorize?: false,
          context: %{from_draft_approve: true}
        )

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 Compensation,
                 %{action_id: action.id, body: "X"},
                 action: :register,
                 actor: operator
               )
    end
  end

  describe "A1: Action.:execute is not replay-able" do
    test "second execute on an already-executed Action fails the StatusTransition guard" do
      %{operator: operator, draft: draft, action: action} = seed_approved_chain()
      backdate!(draft)

      assert {:ok, executed} = Ash.update(action, %{}, action: :execute, actor: operator)
      assert executed.status == :executed

      assert {:error, %Ash.Error.Invalid{} = err} =
               Ash.update(executed, %{}, action: :execute, actor: operator)

      assert Enum.any?(err.errors, fn
               %{message: msg} -> is_binary(msg) and msg =~ "invalid transition from :executed"
               _ -> false
             end)
    end
  end

  describe "R2-1: Inbox.:record_inbox refuses :status and :recorded_by_id as inputs" do
    test ":status is not on the accept list" do
      %{operator: operator, conversation: conversation} = seed_conversation()

      assert {:error, %Ash.Error.Invalid{} = error} =
               Ash.create(
                 Inbox,
                 %{conversation_id: conversation.id, summary: "S", status: :executed},
                 action: :record_inbox,
                 actor: operator
               )

      assert Enum.any?(
               error.errors,
               &match?(%Ash.Error.Invalid.NoSuchInput{input: :status}, &1)
             )
    end

    test ":recorded_by_id is not on the accept list (and the relationship is non-writable)" do
      %{operator: operator, conversation: conversation} = seed_conversation()
      other_user = create_user(:operator)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Ash.create(
                 Inbox,
                 %{
                   conversation_id: conversation.id,
                   summary: "S",
                   recorded_by_id: other_user.id
                 },
                 action: :record_inbox,
                 actor: operator
               )

      assert Enum.any?(
               error.errors,
               &match?(%Ash.Error.Invalid.NoSuchInput{input: :recorded_by_id}, &1)
             )

      {:ok, inbox} =
        Ash.create(
          Inbox,
          %{conversation_id: conversation.id, summary: "S"},
          action: :record_inbox,
          actor: operator
        )

      assert inbox.recorded_by_id == operator.id
    end
  end

  describe "R2-2: Inbox state machine cannot be bypassed by operators" do
    test "operator cannot Ash.update an Inbox to :executed without going through Action.execute" do
      %{operator: operator, inbox: inbox} = seed_open_inbox()

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.update(inbox, %{}, action: :mark_executed, actor: operator)
    end

    test "operator cannot un-dismiss an inbox" do
      %{operator: operator, inbox: inbox} = seed_open_inbox()

      {:ok, dismissed} = Ash.update(inbox, %{}, action: :dismiss, actor: operator)
      assert dismissed.status == :dismissed

      # Trying to transition dismissed → drafting via the open-only
      # mark_drafting action must fail the StatusTransition validation.
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(dismissed, %{}, action: :mark_drafting, actor: operator)
    end
  end

  describe "S3: adapter receives %Message{} struct, not a raw body string" do
    test "Action.execute writes outbound Message with conversation_id + approver populated" do
      %{operator: operator, conversation: conversation, draft: draft, action: action} =
        seed_approved_chain()

      backdate!(draft)

      assert {:ok, _executed} = Ash.update(action, %{}, action: :execute, actor: operator)

      outbound =
        Message
        |> Ash.Query.for_read(:read, %{}, authorize?: false)
        |> Ash.Query.filter(expr(direction == :outbound and conversation_id == ^conversation.id))
        |> Ash.read_one!(authorize?: false)

      refute is_nil(outbound)
      assert outbound.approved_by_id == draft.approved_by_id
      refute is_nil(outbound.sent_at)
    end
  end

  defp backdate!(draft) do
    Ash.update!(
      draft,
      %{approved_at: DateTime.add(DateTime.utc_now(), -10, :second)},
      action: :backdate_approval_for_tests,
      authorize?: false
    )
  end

  defp seed_conversation do
    admin = create_user(:admin)
    operator = create_user(:operator)
    unique = System.unique_integer([:positive])

    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: "Identity #{unique}", primary_identifier: "+1555#{unique}"},
        action: :register_identity,
        actor: admin
      )

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "Thread", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: operator
      )

    %{admin: admin, operator: operator, channel: channel, conversation: conversation}
  end

  defp seed_open_inbox do
    %{operator: operator, conversation: conversation} = ctx = seed_conversation()

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "S"},
        action: :record_inbox,
        actor: operator
      )

    Map.merge(ctx, %{inbox: inbox})
  end

  defp seed_drafting_chain do
    ctx = seed_open_inbox()

    {:ok, draft} =
      Ash.create(
        Draft,
        %{
          inbox_id: ctx.inbox.id,
          body: "Draft body",
          compensation_body: "Compensate",
          status: :drafting
        },
        action: :compose_draft,
        actor: ctx.operator
      )

    Map.merge(ctx, %{draft: draft})
  end

  defp seed_approved_chain do
    ctx = seed_drafting_chain()
    {:ok, approved} = Ash.update(ctx.draft, %{}, action: :approve, actor: ctx.operator)

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!(authorize?: false)

    Map.merge(ctx, %{draft: approved, action: action})
  end

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{email: "#{role}-#{System.unique_integer([:positive])}@example.com", role: role},
        action: :register,
        authorize?: false
      )

    user
  end
end
