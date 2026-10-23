import Config

# runtime.exs is evaluated when the app boots (also inside a release/container),
# so this is where we read environment variables. 12-factor style config.
# "0.2" or "0" -> float (String.to_float/1 rejects "0").
parse_float = fn str ->
  {value, ""} = Float.parse(str)
  value
end

config :call_router,
  port: String.to_integer(System.get_env("PORT", "4000")),
  # Fault injection for demos/chaos tests (see CallRouter.FaultInjection).
  fault_error_rate: parse_float.(System.get_env("FAULT_ERROR_RATE", "0")),
  fault_latency_ms: String.to_integer(System.get_env("FAULT_LATENCY_MS", "0"))

# Tracing: export spans over OTLP only when an endpoint is configured, e.g.
#   OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
# Otherwise traces_exporter stays :none (from config.exs) - a no-op.
if endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry,
    traces_exporter: :otlp,
    span_processor: :batch,
    resource: [
      service: [
        name: System.get_env("OTEL_SERVICE_NAME", "call-router"),
        version: System.get_env("APP_VERSION", "dev")
      ],
      deployment: [environment: System.get_env("DEPLOY_ENV", "local")]
    ]

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: endpoint
end

# Database: with DATABASE_URL set (always on Kubernetes), calls go to
# PostgreSQL; without it they stay in memory (handy for a quick `mix run`).
# On kind/GKE the URL comes from the Secret CloudNativePG creates.
if config_env() != :test do
  if url = System.get_env("DATABASE_URL") do
    # Qualify "<service>.<namespace>" (the CNPG uri secret) to a cluster
    # FQDN when the chart sets DATABASE_CLUSTER_DOMAIN. The pool already
    # reconnects; boot migrations retry in CallRouter.Migrator.
    url = CallRouter.DatabaseUrl.qualify(url, System.get_env("DATABASE_CLUSTER_DOMAIN"))

    config :call_router, CallRouter.Repo,
      url: url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE", "5")),
      # Fail fast instead of queueing forever when the DB is gone.
      queue_target: 500,
      queue_interval: 1_000,
      # TLS on GKE/Cloud SQL; CNPG on kind accepts plain connections in-cluster.
      ssl: System.get_env("DATABASE_SSL", "false") == "true"

    config :call_router,
      store: :postgres,
      run_migrations: System.get_env("RUN_MIGRATIONS", "true") == "true"
  end
end

if level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end
