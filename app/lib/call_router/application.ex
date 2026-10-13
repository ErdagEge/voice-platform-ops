defmodule CallRouter.Application do
  @moduledoc """
  OTP application entry point.

  It starts a *supervision tree*: if a child process crashes, its supervisor
  restarts it. Order matters - the stores must exist before the web server
  accepts requests that use them.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:call_router, :port, 4000)

    children =
      [
        CallRouter.Metrics,
        CallRouter.CallStore
      ] ++ server_children(port)

    opts = [strategy: :one_for_one, name: CallRouter.Supervisor]
    result = Supervisor.start_link(children, opts)
    Logger.info("call_router started on port #{port}")
    result
  end

  # In tests we call the router directly, so we skip binding a TCP port.
  defp server_children(port) do
    if Application.get_env(:call_router, :start_server, true) do
      [{Bandit, plug: CallRouter.Router, scheme: :http, port: port}]
    else
      []
    end
  end
end
