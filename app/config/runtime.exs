import Config

# runtime.exs is evaluated when the app boots (also inside a release/container),
# so this is where we read environment variables. 12-factor style config.
config :call_router,
  port: String.to_integer(System.get_env("PORT", "4000"))

if level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end
