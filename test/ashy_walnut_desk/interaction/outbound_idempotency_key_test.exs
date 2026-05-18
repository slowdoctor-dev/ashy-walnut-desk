defmodule AshyWalnutDesk.Interaction.OutboundIdempotencyKeyTest do
  @moduledoc """
  Story 3.4 AC2 — `Action.outbound_idempotency_key` is stamped at
  `:register_pending` time, deterministic per Action row, stable
  across re-reads. Story 3.5 uses it as Twilio's `Idempotency-Key`
  header so Oban retries don't double-send.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.InteractionFixtures

  test "Action gets a non-nil outbound_idempotency_key from :register_pending" do
    %{action: action} = InteractionFixtures.seed_approved_chain()

    assert is_binary(action.outbound_idempotency_key)
    assert String.starts_with?(action.outbound_idempotency_key, "action-")
    assert byte_size(action.outbound_idempotency_key) > byte_size("action-")
  end

  test "outbound_idempotency_key is stable across re-reads" do
    %{action: action} = InteractionFixtures.seed_approved_chain()

    {:ok, reloaded} =
      Ash.get(AshyWalnutDesk.Interaction.Action, action.id, authorize?: false)

    assert reloaded.outbound_idempotency_key == action.outbound_idempotency_key
  end

  test "different Actions get different keys" do
    admin = AshyWalnutDesk.AccountsFixtures.create_user(:admin)
    %{action: a} = InteractionFixtures.seed_approved_chain(admin: admin)
    %{action: b} = InteractionFixtures.seed_approved_chain(admin: admin)

    refute a.outbound_idempotency_key == b.outbound_idempotency_key
  end
end
