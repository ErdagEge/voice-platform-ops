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

if level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end
