import Config

# Emit every log line as a single JSON object (see CallRouter.LogFormatter).
# Log aggregators (Loki, Cloud Logging) can then index fields directly.
config :logger, :default_formatter,
  format: {CallRouter.LogFormatter, :format},
  metadata: [:request_id, :call_id, :method, :path, :status, :duration_ms]

import_config "#{config_env()}.exs"
