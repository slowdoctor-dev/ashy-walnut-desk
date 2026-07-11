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

# pgvector: Postgrex needs the custom types module (defined in
# lib/ashy_walnut_desk/postgrex_types.ex) to encode/decode the `vector`
# columns on manual_chunks. Merged into every env's Repo config.
config :ashy_walnut_desk, AshyWalnutDesk.Repo, types: AshyWalnutDesk.PostgrexTypes

config :ashy_walnut_desk,
  ecto_repos: [AshyWalnutDesk.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  ash_domains: [
    AshyWalnutDesk.Accounts,
    AshyWalnutDesk.Identity,
    AshyWalnutDesk.Interaction,
    AshyWalnutDesk.Knowledge,
    AshyWalnutDesk.AI
  ]

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

config :ashy_walnut_desk, :channel_adapters, [
  AshyWalnutDesk.Interaction.Adapters.Stub,
  AshyWalnutDesk.Interaction.Adapters.Twilio
]

# Model strings a Persona may select via `model_override`. Distinct from
# `:ai_adapter_allowlist` (adapter MODULES), which story 4.3 introduces
# mirroring `:channel_adapters` above.
config :ashy_walnut_desk, :ai_model_allowlist, [
  "claude-sonnet-4-6",
  "claude-opus-4-7"
]

config :ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Fixture

config :ashy_walnut_desk, :ai_adapter_allowlist, [
  AshyWalnutDesk.AI.Adapters.Fixture,
  AshyWalnutDesk.AI.Adapters.Anthropic
]

config :ashy_walnut_desk, :deployment_validators, []

# Default model when a Persona supplies no `model_override`. Must be a
# member of `:ai_model_allowlist` above. `config/runtime.exs` flips
# `:ai_adapter` to the real Anthropic impl in `:prod`.
config :ashy_walnut_desk, :default_model, "claude-sonnet-4-6"

# Knowledge-axis embedding boundary (ADR-026, story 5.2). Fixture is
# the offline dev/test default; `config/runtime.exs` requires an
# explicit EMBEDDING_ADAPTER choice (voyage | none) in :prod so
# external data egress is always a deliberate deployer decision.
config :ashy_walnut_desk, :embedding_adapter, AshyWalnutDesk.Knowledge.Embedders.Fixture

config :ashy_walnut_desk, :embedding_adapter_allowlist, [
  AshyWalnutDesk.Knowledge.Embedders.Fixture,
  AshyWalnutDesk.Knowledge.Embedders.Voyage
]

config :ashy_walnut_desk, :embedding_model, "voyage-3.5-lite"
config :ashy_walnut_desk, :embedding_model_allowlist, ["voyage-3.5-lite", "voyage-3.5"]

# Must match the pgvector column dimension on manual_chunks (story 5.3);
# changing it is a migration + full re-embed event.
config :ashy_walnut_desk, :embedding_dimension, 1024

# Retrieval ladder tuning (story 5.4). `enabled?: false` is the
# kill-switch that restores exact Phase 4 generation behavior.
config :ashy_walnut_desk, :retrieval,
  enabled?: true,
  top_k: 4,
  min_score: 0.5,
  token_budget: 1_200

# F6: strict CSP is prod-only because Phoenix's dev tooling
# (LiveReloader + LiveDashboard) injects inline scripts that
# `script-src 'self'` blocks — Chromium silently aborts the
# resulting LV WebSocket, breaking dev + headless screenshot capture.
# Flipped on in `config/prod.exs`.
config :ashy_walnut_desk, :strict_csp?, false

# Framework default: registration disabled. Flipped to `true` in
# `config/dev.exs` and `config/test.exs` for local workflow. In prod,
# `config/runtime.exs` reads `AWD_REGISTRATION_ENABLED` (1/true). When
# off, `Accounts.Changes.RegistrationGate` rejects magic-link sign-in
# attempts from unknown emails — see F1 in the Phase 2 security review.
config :ashy_walnut_desk, :registration_enabled?, false

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
