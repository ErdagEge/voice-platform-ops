import Config

# Keep test output quiet, and don't bind a real port during tests.
config :logger, level: :warning
config :call_router, start_server: false
