import Config

# Story 3.fix: `:identifier_hash_salt` and `:ash_authentication_secret`
# are set explicitly in `config/dev.exs` and `config/test.exs` so a
# prod misconfiguration cannot silently fall back to a dev-only
# default at this top level. The `:prod` block below enforces them
# from env vars and raises at boot if either is missing.

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ashy_walnut_desk start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint, server: true
end

config :ashy_walnut_desk, Oban,
  queues: [
    default: 10,
    messages: 10,
    ai: 5,
    reindex: 5,
    tokens: 5,
    outbound: 5,
    ai_generation: 5
  ]

if config_env() == :prod do
  # Stamp the runtime env so prod-only code paths (e.g.
  # `Adapters.Twilio.fallback_credential!/1`) can fail-loud instead
  # of returning a dev placeholder.
  config :ashy_walnut_desk, :env, :prod

  # F1 — registration gate. Default false; deployer opts in by setting
  # AWD_REGISTRATION_ENABLED=1 once their allowlist / invite flow / SSO
  # replacement is in place. Without this, the magic-link strategy
  # admits any email to the `:operator` role on first sign-in, which is
  # materially unsafe for the regulated-services target domain
  # (BASELINE §3).
  if System.get_env("AWD_REGISTRATION_ENABLED") in ~w(1 true) do
    config :ashy_walnut_desk, :registration_enabled?, true
  end

  # Story 3.fix — Twilio prod credentials must be set when the
  # framework is built with the Twilio adapter in the
  # `:channel_adapters` allowlist (the framework default). Missing
  # creds in prod would otherwise fall through to the adapter's
  # placeholder strings and produce a 401 from Twilio on every send.
  # Enforced regardless of whether a `Channel{adapter_module:
  # Twilio}` row exists — registering one without creds wired would
  # be the same misconfiguration.
  twilio_account_sid =
    System.get_env("TWILIO_ACCOUNT_SID") ||
      raise """
      environment variable TWILIO_ACCOUNT_SID is missing.
      Get it from https://console.twilio.com (Account Info).
      """

  twilio_auth_token =
    System.get_env("TWILIO_AUTH_TOKEN") ||
      raise """
      environment variable TWILIO_AUTH_TOKEN is missing.
      Get it from https://console.twilio.com (Account Info).
      Treat this as a secret — leaking it allows forging webhook
      signatures (X-Twilio-Signature) per ADR-024.
      """

  twilio_from_number =
    System.get_env("TWILIO_FROM_NUMBER") ||
      raise """
      environment variable TWILIO_FROM_NUMBER is missing.
      The E.164 (+1…) number you bought / registered with Twilio.
      """

  config :ashy_walnut_desk, :twilio,
    account_sid: twilio_account_sid,
    auth_token: twilio_auth_token,
    from_number: twilio_from_number

  # Webhook signature verification: the signature plug refuses to
  # bypass when this is true. In prod we set both — the secret AND
  # the requirement flag — so a future code path that forgets to
  # check the flag can't silently accept unsigned webhooks.
  config :ashy_walnut_desk, :twilio_auth_token, twilio_auth_token
  config :ashy_walnut_desk, :twilio_signature_required, true

  # Sec-fix R3: pin the canonical webhook URL used in signature
  # verification. Twilio computed `X-Twilio-Signature` over the URL
  # it POSTed to; if the deployer is behind a reverse proxy that
  # rewrites Host, reconstructing from `conn.host` produces a
  # different string and verification fails for legitimate requests.
  # Required when the webhook lives behind a proxy; optional
  # otherwise.
  if url = System.get_env("TWILIO_WEBHOOK_URL") do
    config :ashy_walnut_desk, :twilio_webhook_url, url
  end

  # AI generation (ADR-025, story 4.3). Fail fast at boot if the
  # provider key is missing — otherwise the Anthropic adapter would
  # fall through to its dev placeholder and 401 on the first
  # generation. In prod the real adapter is the default; dev/test use
  # the deterministic Fixture (set in config/config.exs), so the key
  # is only required here.
  anthropic_api_key =
    System.get_env("ANTHROPIC_API_KEY") ||
      raise """
      environment variable ANTHROPIC_API_KEY is missing.
      Get it from https://console.anthropic.com (API keys).
      Treat this as a secret — it is never logged or persisted in
      Draft.ai_* fields or AuditEvent rows (AGENTS.md §7.4).
      """

  config :ashy_walnut_desk, :anthropic, api_key: anthropic_api_key
  config :ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Anthropic

  # Knowledge embeddings (ADR-026, story 5.2). The adapter choice is an
  # explicit deployer decision — "voyage" sends Manual content to the
  # external embedding provider; "none" keeps all knowledge in-instance
  # (retrieval degrades to the pg_trgm lexical rung). No silent default.
  case System.get_env("EMBEDDING_ADAPTER") do
    "voyage" ->
      voyage_api_key =
        System.get_env("VOYAGE_API_KEY") ||
          raise """
          EMBEDDING_ADAPTER=voyage requires VOYAGE_API_KEY.
          Get it from https://dash.voyageai.com (API keys).
          Treat this as a secret — it is never logged or persisted
          (AGENTS.md §7.4).
          """

      config :ashy_walnut_desk, :voyage, api_key: voyage_api_key
      config :ashy_walnut_desk, :embedding_adapter, AshyWalnutDesk.Knowledge.Embedders.Voyage

    "none" ->
      config :ashy_walnut_desk, :embedding_adapter, nil

    other ->
      raise """
      environment variable EMBEDDING_ADAPTER is #{inspect(other)}; set it
      to "voyage" (external embeddings via Voyage AI — Manual content
      leaves this instance) or "none" (no external embeddings; retrieval
      uses lexical matching only). See ADR-026 and the Phase 5 runbook.
      """
  end

  identifier_hash_salt =
    System.get_env("IDENTIFIER_HASH_SALT") ||
      raise """
      environment variable IDENTIFIER_HASH_SALT is missing.
      Generate one with: openssl rand -hex 32
      """

  config :ashy_walnut_desk, identifier_hash_salt: identifier_hash_salt

  ash_authentication_secret =
    System.get_env("ASH_AUTHENTICATION_SECRET") ||
      raise """
      environment variable ASH_AUTHENTICATION_SECRET is missing.
      The Accounts.User.JwtSecret module reads it at runtime; without it,
      all JWTs would be signed with the dev-only fallback constant.
      Generate one with: mix phx.gen.secret
      """

  if byte_size(ash_authentication_secret) < 64 do
    raise """
    environment variable ASH_AUTHENTICATION_SECRET is too short
    (got #{byte_size(ash_authentication_secret)} bytes; require >= 64).
    Phoenix.gen.secret produces 64-byte values. A short signing secret
    weakens JWT signature strength even though presence is enforced.
    Generate a fresh one with: mix phx.gen.secret
    """
  end

  config :ashy_walnut_desk, ash_authentication_secret: ash_authentication_secret

  # ADR-021 — prod TLS + secure-cookie hardening keyed on PHX_HOST.
  # Dev / test (no PHX_HOST set, or set to "localhost") keep the base
  # `session_options` from `config.exs` so local HTTP works. A real
  # host triggers `force_ssl: [hsts: true]` and merges `secure: true`
  # + `http_only: true` into the session cookie. Closes TO-2.
  if System.get_env("PHX_HOST", "localhost") != "localhost" do
    base = Application.get_env(:ashy_walnut_desk, :session_options, [])

    config :ashy_walnut_desk, :session_options, Keyword.merge(base, secure: true, http_only: true)

    config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint, force_ssl: [hsts: true]
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ashy_walnut_desk, AshyWalnutDesk.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ashy_walnut_desk, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
