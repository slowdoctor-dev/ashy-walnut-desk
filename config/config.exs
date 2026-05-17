# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ashy_walnut_desk, Oban,
  name: Oban,
  repo: AshyWalnutDesk.Repo,
  plugins: [Oban.Plugins.Pruner, {Oban.Plugins.Cron, crontab: []}],
  queues: []

config :ashy_walnut_desk,
  ecto_repos: [AshyWalnutDesk.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  ash_domains: [AshyWalnutDesk.Accounts, AshyWalnutDesk.Identity]

# Base session-cookie options. `runtime.exs` `:prod` block merges
# `secure: true` + `http_only: true` when `PHX_HOST != "localhost"`
# (ADR-021). The endpoint's `put_session_options` plug reads this
# at request time so runtime overrides win.
config :ashy_walnut_desk, :session_options,
  store: :cookie,
  key: "_ashy_walnut_desk_key",
  signing_salt: "xwQ+0Tlz",
  same_site: "Lax"

# AshPaperTrail app-level setup for later per-resource opt-in.
config :ash_paper_trail,
  repo: AshyWalnutDesk.Repo

# Configures the endpoint
config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AshyWalnutDeskWeb.ErrorHTML, json: AshyWalnutDeskWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AshyWalnutDesk.PubSub,
  live_view: [signing_salt: "6hX+x3Zw"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  ashy_walnut_desk: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  ashy_walnut_desk: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ashy_walnut_desk, AshyWalnutDesk.Mailer, adapter: Swoosh.Adapters.Local

config :swoosh, :api_client, false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
