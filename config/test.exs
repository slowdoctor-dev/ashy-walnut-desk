import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ashy_walnut_desk, AshyWalnutDesk.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ashy_walnut_desk_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Xt4k65DjUHXZ4pTVCy79ofBk0A6odis0v6W+JGEfs8Nb3vX23ZMlP9s4aRbS0HAN",
  server: false

# Run Oban in manual testing mode so AshOban triggers can be driven
# synchronously by AshOban.Test.schedule_and_run_triggers/2 against the
# sandbox connection (no background queue picks up sandboxed jobs).
config :ashy_walnut_desk, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :ashy_walnut_desk, AshyWalnutDesk.Mailer, adapter: Swoosh.Adapters.Test

# Test-only: extend the prod allowlist with the Echo adapter so the
# adapter-contract conformance suite (story 3.2) can drive both
# Twilio and Echo through the same scenarios. Echo is forbidden in
# prod by virtue of NOT being in config/config.exs's allowlist.
config :ashy_walnut_desk, :channel_adapters, [
  AshyWalnutDesk.Interaction.Adapters.Stub,
  AshyWalnutDesk.Interaction.Adapters.Twilio,
  AshyWalnutDesk.Interaction.Adapters.Echo
]

# Existing magic-link / fixture tests register fresh users. Tests that
# pin the F1 gate flip this back to false on a per-test basis.
config :ashy_walnut_desk, :registration_enabled?, true
