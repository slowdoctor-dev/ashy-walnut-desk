defmodule AshyWalnutDesk.ObanSetupTest do
  use ExUnit.Case, async: false

  test "Oban is supervised and queues are configured" do
    assert {Oban, pid, :supervisor, [Oban]} =
             Enum.find(
               Supervisor.which_children(AshyWalnutDesk.Supervisor),
               fn {id, _pid, _type, _modules} -> id == Oban end
             )

    assert is_pid(pid)
    assert is_pid(Oban.Registry.whereis(Oban))

    # Oban runs in `testing: :manual` mode in test env, so the running
    # supervisor reports `queues: []`. Assert on the configured queues
    # (the source of truth for what `:prod` / `:dev` will start) instead.
    configured_queues = Application.fetch_env!(:ashy_walnut_desk, Oban)[:queues]

    assert configured_queues == [
             default: 10,
             messages: 10,
             ai: 5,
             reindex: 5,
             tokens: 5,
             outbound: 5,
             ai_generation: 5
           ]
  end
end
