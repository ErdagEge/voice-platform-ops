defmodule CallRouter.CallStore do
  @moduledoc """
  Where routed calls are stored. A *behaviour* (Elixir's word for an
  interface) with two implementations:

    * `CallRouter.CallStore.Postgres` - the real one, used whenever
      `DATABASE_URL` is set (always on Kubernetes). Every replica sees the
      same data, and it survives restarts, so backups/DR make sense.
    * `CallRouter.CallStore.Memory` - ETS fallback for running the app
      without a database.

  Callers use this module; it forwards to the backend chosen in config
  (`config :call_router, store: :postgres | :memory`).
  """

  @typedoc "A routed call as returned by the API."
  @type call :: %{required(:call_id) => String.t(), optional(atom()) => term()}

  @callback put(call()) :: {:ok, call()} | {:error, :unavailable}
  @callback get(String.t()) :: {:ok, call()} | {:error, :not_found | :unavailable}
  @callback ready?() :: boolean()

  def put(call), do: backend().put(call)
  def get(id), do: backend().get(id)
  def ready?, do: backend().ready?()

  @doc "The configured backend module."
  def backend do
    case Application.get_env(:call_router, :store, :memory) do
      :postgres -> CallRouter.CallStore.Postgres
      :memory -> CallRouter.CallStore.Memory
      # Any module implementing the behaviour (tests use a failing fake).
      module when is_atom(module) -> module
    end
  end

  @doc "Processes the backend needs in the supervision tree."
  def children do
    case Application.get_env(:call_router, :store, :memory) do
      :postgres ->
        # Repo = connection pool (it reconnects on its own). Migrations go
        # through CallRouter.Migrator, which retries: Ecto.Migrator's one-shot
        # init crashes the VM on a DNS failure (chaos experiment 03).
        [CallRouter.Repo] ++ migration_children()

      :memory ->
        [CallRouter.CallStore.Memory]
    end
  end

  defp migration_children do
    if Application.get_env(:call_router, :run_migrations, true) do
      [{CallRouter.Migrator, repo: CallRouter.Repo}]
    else
      []
    end
  end
end
