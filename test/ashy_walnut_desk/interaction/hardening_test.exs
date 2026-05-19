defmodule AshyWalnutDesk.Interaction.HardeningTest do
  @moduledoc """
  Regression tests for the Phase 2 implementation hardening pass.
  Each test pins a specific bypass that was open after the original
  Phase 2 implementation merged and was closed by the merged PRs.

  Findings indexed by their R1/R2 review ID; see PR descriptions
  for #37 (implementation) and #38 (security).
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.{AccountsFixtures, InteractionFixtures}

  alias AshyWalnutDesk.Interaction.{
    Action,
    Compensation,
    Inbox,
    Message
  }

  describe "S1: Draft.:revise cannot stamp approval fields" do
    test "rejects :approved_at and :approved_by_id as inputs (countdown bypass)" do
      %{operator: operator, draft: draft} = drafting_chain()

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

    # Test-fix R6: `:revise` validates `StatusTransition, from:
    # [:drafting]`. Once approved, the draft is sealed — the
    # countdown is anchored on `approved_at` and the operator
    # cannot edit the body out from under the chain. Pin the
    # rejection so a future change to the from-state list
    # (e.g. accidentally adding :approved to allow re-edits)
    # surfaces as a failing test.
    test "rejects :revise on an :approved draft (state transition)" do
      %{operator: operator, draft: draft} = drafting_chain()

      {:ok, approved} =
        Ash.update(draft, %{compensation_body: "X"}, action: :approve, actor: operator)

      assert approved.status == :approved

      assert {:error, %Ash.Error.Invalid{} = error} =
               Ash.update(approved, %{body: "tampered"}, action: :revise, actor: operator)

      assert Enum.any?(error.errors, fn
               %{message: msg} -> is_binary(msg) and msg =~ "invalid transition from :approved"
               _ -> false
             end)
    end
  end

  describe "S2/R2-3: register_pending + register are internal-only" do
    test "operator cannot create Action.:register_pending directly" do
      %{operator: operator, draft: draft, channel: channel} = drafting_chain()

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 Action,
                 %{draft_id: draft.id, channel_id: channel.id},
                 action: :register_pending,
                 actor: operator
               )
    end

    test "operator cannot create Compensation.:register directly" do
      %{operator: operator, draft: draft, channel: channel} = drafting_chain()

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
      %{operator: operator, draft: draft, action: action} =
        InteractionFixtures.seed_approved_chain()

      InteractionFixtures.backdate_approval!(draft)

      executed = InteractionFixtures.execute_action!(action, operator)
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
      %{operator: operator, conversation: conversation} = conversation_only()

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
      %{operator: operator, conversation: conversation} = conversation_only()
      other_user = AccountsFixtures.create_user(:operator)

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

      inbox = InteractionFixtures.seed_inbox(operator, conversation, summary: "S")
      assert inbox.recorded_by_id == operator.id
    end
  end

  describe "R2-2: Inbox state machine cannot be bypassed by operators" do
    test "operator cannot Ash.update an Inbox to :executed without going through Action.execute" do
      %{operator: operator, inbox: inbox} = open_inbox()

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.update(inbox, %{}, action: :mark_executed, actor: operator)
    end

    test "operator cannot un-dismiss an inbox" do
      %{operator: operator, inbox: inbox} = open_inbox()

      {:ok, dismissed} = Ash.update(inbox, %{}, action: :dismiss, actor: operator)
      assert dismissed.status == :dismissed

      # Trying to transition dismissed → drafting via the open-only
      # mark_drafting action must fail the StatusTransition validation.
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(dismissed, %{}, action: :mark_drafting, actor: operator)
    end
  end

  describe "F4: Action.:execute respects channel.enabled? (security review)" do
    test "disabled channel produces :failed action with a clear error and no outbound Message" do
      %{admin: admin, operator: operator, channel: channel, draft: draft, action: action} =
        InteractionFixtures.seed_approved_chain()

      InteractionFixtures.backdate_approval!(draft)

      {:ok, _} = Ash.update(channel, %{}, action: :disable, actor: admin)

      executed = InteractionFixtures.execute_action!(action, operator)
      assert executed.status == :failed
      assert is_binary(executed.error) and executed.error =~ "disabled"

      outbound =
        Message
        |> Ash.Query.for_read(:read, %{}, authorize?: false)
        |> Ash.Query.filter(expr(direction == :outbound))
        |> Ash.read!(authorize?: false)

      assert outbound == [],
             "disabled channel still produced an outbound Message — F4 regression"
    end
  end

  describe "S3: adapter receives %Message{} struct, not a raw body string" do
    test "Action.execute writes outbound Message with conversation_id + approver populated" do
      %{operator: operator, conversation: conversation, draft: draft, action: action} =
        InteractionFixtures.seed_approved_chain()

      InteractionFixtures.backdate_approval!(draft)

      _executed = InteractionFixtures.execute_action!(action, operator)

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

  # The shared fixtures don't stop at "just a conversation" or
  # "just an open inbox" — but these tests exercise pre-chain
  # states. Build the chain in pieces here.

  defp conversation_only do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = InteractionFixtures.seed_identity(admin)
    channel = InteractionFixtures.seed_channel(admin)
    conversation = InteractionFixtures.seed_conversation(operator, identity, channel)

    %{admin: admin, operator: operator, channel: channel, conversation: conversation}
  end

  defp open_inbox do
    ctx = conversation_only()
    inbox = InteractionFixtures.seed_inbox(ctx.operator, ctx.conversation, summary: "S")
    Map.put(ctx, :inbox, inbox)
  end

  defp drafting_chain do
    ctx = open_inbox()
    draft = InteractionFixtures.seed_draft(ctx.operator, ctx.inbox)
    Map.put(ctx, :draft, draft)
  end
end
