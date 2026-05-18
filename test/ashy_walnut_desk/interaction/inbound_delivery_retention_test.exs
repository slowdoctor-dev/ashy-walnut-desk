defmodule AshyWalnutDesk.Interaction.InboundDeliveryRetentionTest do
  @moduledoc """
  Story 3.4 AC4 — `InboundDelivery.:expunge_expired` removes rows
  older than the retention window (7 days per ADR-024 C1) via the
  daily AshOban trigger. Mirrors the Token-expunge pattern that
  resolved TO-3.
  """

  use AshyWalnutDesk.DataCase, async: false
  require Ash.Query

  alias AshyWalnutDesk.Interaction.InboundDelivery
  alias AshyWalnutDesk.Repo

  # Oban runs in `testing: :manual` already (see config/test.exs); no
  # per-test app-env mutation needed. Mutating `:ashy_walnut_desk, Oban`
  # would leak into `AshyWalnutDesk.ObanSetupTest` which asserts on the
  # configured queues.

  test "retention_days is 7 (ADR-024 C1)" do
    assert InboundDelivery.retention_days() == 7
  end

  test ":expunge_expired drops rows older than retention_days" do
    # Insert a row dated 10 days ago directly via SQL (Ash actions
    # can't backdate received_at). The expunge filters by it.
    old_id = Ecto.UUID.generate()
    {old_id_bin, _} = Ecto.UUID.dump(old_id) |> then(&{elem(&1, 1), :ok})

    fresh_id = Ecto.UUID.generate()
    {fresh_id_bin, _} = Ecto.UUID.dump(fresh_id) |> then(&{elem(&1, 1), :ok})

    now = DateTime.utc_now()
    ten_days_ago = DateTime.add(now, -10 * 86_400, :second)

    Repo.query!(
      """
      INSERT INTO inbound_deliveries
        (id, provider, provider_message_id, received_at, outcome, created_at)
      VALUES ($1, $2, $3, $4, $5, $6), ($7, $2, $8, $9, $5, $9)
      """,
      [
        old_id_bin,
        "twilio",
        "SM-old-#{System.unique_integer([:positive])}",
        ten_days_ago,
        "processed",
        ten_days_ago,
        fresh_id_bin,
        "SM-fresh-#{System.unique_integer([:positive])}",
        now
      ]
    )

    # Drive the trigger manually.
    AshOban.Test.schedule_and_run_triggers(InboundDelivery)

    remaining =
      InboundDelivery
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    refute old_id in remaining
    assert fresh_id in remaining
  end
end
