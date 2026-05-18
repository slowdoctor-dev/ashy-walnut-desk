defmodule AshyWalnutDesk.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias AshyWalnutDesk.Accounts.SystemActor
  alias AshyWalnutDeskWeb.Plugs.RateLimit

  @impl true
  def start(_type, _args) do
    # F2/A2: ensure the per-IP rate-limit ETS table exists before any
    # request can reach `AshyWalnutDeskWeb.Plugs.RateLimit`. Idempotent.
    RateLimit.start_table()

    children = [
      AshyWalnutDeskWeb.Telemetry,
      AshyWalnutDesk.Repo,
      {DNSCluster, query: Application.get_env(:ashy_walnut_desk, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AshyWalnutDesk.PubSub},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:ashy_walnut_desk, :ash_domains),
         Application.fetch_env!(:ashy_walnut_desk, Oban)
       )},
      # Start a worker by calling: AshyWalnutDesk.Worker.start_link(arg)
      # {AshyWalnutDesk.Worker, arg},
      # Start to serve requests, typically the last entry
      AshyWalnutDeskWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshyWalnutDesk.Supervisor]
    result = Supervisor.start_link(children, opts)

    # ADR-024: the inbound-webhook system actor must exist before
    # any /webhook/twilio request can land. The Repo child started
    # above; this runs after it's up.
    case result do
      {:ok, _} -> _ = SystemActor.ensure!()
      _ -> :noop
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshyWalnutDeskWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
