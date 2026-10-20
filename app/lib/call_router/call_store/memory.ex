defmodule CallRouter.CallStore.Memory do
  @moduledoc """
  In-memory call storage backed by ETS (Erlang Term Storage).

  A GenServer *owns* the ETS table (the table dies if its owner dies), while
  reads/writes go straight to the table for speed.

  Only used when no database is configured (e.g. `mix run` on a laptop).
  Data lives in *one* pod's memory: it is lost on restart and other replicas
  cannot see it - which is why Kubernetes deployments use the Postgres store.
  """
  use GenServer
  @behaviour CallRouter.CallStore

  @table :call_router_calls

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl CallRouter.CallStore
  def put(%{call_id: id} = call) do
    :ets.insert(@table, {id, call})
    {:ok, call}
  end

  @impl CallRouter.CallStore
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, call}] -> {:ok, call}
      [] -> {:error, :not_found}
    end
  end

  @impl CallRouter.CallStore
  def ready?, do: :ets.whereis(@table) != :undefined

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
