defmodule Mix.Tasks.Audit.Verify do
  @moduledoc false
  use Mix.Task

  alias AshyWalnutDesk.Interaction.AuditChain

  @shortdoc "Verifies hash continuity for all audit chains"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    AuditChain.all_chain_topics()
    |> Enum.reduce_while(:ok, fn topic, :ok ->
      case AuditChain.walk(topic) do
        {:ok, _events} ->
          {:cont, :ok}

        {:error, {:broken_at, event_id}} ->
          Mix.shell().error("audit.verify broken event_id=#{event_id} chain_topic=#{topic}")
          {:halt, :error}
      end
    end)
    |> case do
      :ok ->
        Mix.shell().info("audit.verify ok")
        :ok

      :error ->
        Mix.raise("audit.verify failed")
    end
  end
end
