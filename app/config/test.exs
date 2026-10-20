import Config

# Keep test output quiet, and don't bind a real port during tests.
config :logger, level: :warning
config :call_router, start_server: false

# Tests run against a real PostgreSQL (CI: a `postgres` service container;
# locally: `docker run -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:18-alpine`).
# The SQL Sandbox wraps every test in a transaction that is rolled back.
config :call_router, CallRouter.Repo,
  url: System.get_env("DATABASE_URL", "ecto://postgres:postgres@localhost:5432/call_router_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :call_router,
  store: :postgres,
  # mix test migrates via the alias in mix.exs, not at boot.
  run_migrations: false,
  db_health_interval_ms: 0
