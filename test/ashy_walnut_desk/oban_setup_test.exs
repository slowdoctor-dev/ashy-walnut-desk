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

    assert Oban.config().queues == [
             default: [limit: 10],
             messages: [limit: 10],
             ai: [limit: 5],
             reindex: [limit: 5]
           ]
  end
end
