defmodule CallRouter.DbHealth do
  @moduledoc """
  Every few seconds, checks whether PostgreSQL answers and publishes the
  result as the `call_router_db_up` gauge (1 = reachable, 0 = not).

  Readiness already reacts to the database, but a pod that is not ready
  receives no traffic, so request metrics go quiet exactly when the DB is
  down. This gauge keeps reporting, which is what the CallRouterDatabaseDown
  alert uses.

  Disabled (interval 0) in tests and when calls are stored in memory.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    interval = Application.get_env(:call_router, :db_health_interval_ms, 5_000)

    if interval > 0 and CallRouter.CallStore.backend() == CallRouter.CallStore.Postgres do
      send(self(), :check)
      {:ok, interval}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:check, interval) do
    up = if CallRouter.CallStore.ready?(), do: 1, else: 0
    :telemetry.execute([:call_router, :db], %{up: up}, %{})
    Process.send_after(self(), :check, interval)
    {:noreply, interval}
  end
end
