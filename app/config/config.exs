import Config

# Emit every log line as a single JSON object (see CallRouter.LogFormatter).
# Log aggregators (Loki, Cloud Logging) can then index fields directly.
config :logger, :default_formatter,
  format: {CallRouter.LogFormatter, :format},
  metadata: [
    :request_id,
    :trace_id,
    :span_id,
    :call_id,
    :method,
    :route,
    :path,
    :status,
    :duration_ms
  ]

# Tracing is off unless runtime.exs finds OTEL_EXPORTER_OTLP_ENDPOINT.
config :opentelemetry,
  resource: [service: [name: "call-router"]],
  traces_exporter: :none

import_config "#{config_env()}.exs"
