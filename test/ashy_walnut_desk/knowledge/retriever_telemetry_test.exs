defmodule AshyWalnutDesk.Knowledge.RetrieverTelemetryTest do
  @moduledoc """
  Story 5.4 AC5 — `[:awd, :knowledge, :retrieval, :stop]` fires with
  duration/chunk_count measurements and mode/draft_id metadata.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, Retriever}

  setup do
    handler_id = "retriever-telemetry-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:awd, :knowledge, :retrieval, :stop],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:retrieval_stop, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "stop event carries duration, chunk_count, mode, and draft_id" do
    admin = AccountsFixtures.create_user(:admin)

    Ash.create!(
      Manual,
      %{
        title: "Telemetry manual",
        slug: "telemetry-manual",
        body: "Appointment scheduling policy: confirm requested time."
      },
      action: :author,
      actor: admin
    )

    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

    {:ok, result} =
      Retriever.retrieve("appointment scheduling policy confirm requested time",
        draft_id: "draft-123"
      )

    assert result.mode == :vector

    assert_received {:retrieval_stop, measurements, metadata}
    assert is_integer(measurements.duration)
    assert measurements.chunk_count == length(result.excerpts)
    assert metadata.mode == :vector
    assert metadata.draft_id == "draft-123"
  end

  test "none mode also emits (disabled short-circuit)" do
    prev = Application.get_env(:ashy_walnut_desk, :retrieval)
    Application.put_env(:ashy_walnut_desk, :retrieval, enabled?: false)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :retrieval, prev) end)

    {:ok, _result} = Retriever.retrieve("anything")

    assert_received {:retrieval_stop, measurements, metadata}
    assert measurements.chunk_count == 0
    assert metadata.mode == :none
  end
end
