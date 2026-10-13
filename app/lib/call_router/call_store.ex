defmodule CallRouter.CallStore do
  @moduledoc """
  In-memory call storage backed by ETS (Erlang Term Storage).

  A GenServer *owns* the ETS table (the table dies if its owner dies), while
  reads/writes go straight to the table for speed. Data is lost on restart -
  that is intentional for now; a real system would use a database.
  """
  use GenServer

  @table :call_router_calls

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Store (or overwrite) a call map keyed by its id."
  def put(%{call_id: id} = call) do
    :ets.insert(@table, {id, call})
    call
  end

  @doc "Fetch a call by id."
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, call}] -> {:ok, call}
      [] -> :error
    end
  end

  @doc "True when the table exists - used by the readiness probe."
  def ready?, do: :ets.whereis(@table) != :undefined

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
