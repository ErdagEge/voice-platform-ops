defmodule CallRouter.CallStore.Postgres do
  @moduledoc """
  PostgreSQL call storage via Ecto (Elixir's database library).

  Database errors are turned into `{:error, :unavailable}` instead of
  crashing the request, so the router can answer a clean 503 - which the
  availability SLI then counts as an error.
  """
  @behaviour CallRouter.CallStore
  require Logger

  alias CallRouter.{Call, Repo}
  alias Ecto.Adapters.SQL

  @impl true
  def put(call) do
    case call |> Call.changeset() |> Repo.insert() do
      {:ok, row} -> {:ok, Call.to_map(row)}
      {:error, changeset} -> raise "invalid call: #{inspect(changeset.errors)}"
    end
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> unavailable(e)
  end

  @impl true
  def get(id) do
    case Repo.get(Call, id) do
      nil -> {:error, :not_found}
      row -> {:ok, Call.to_map(row)}
    end
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> unavailable(e)
  end

  @doc """
  Readiness: can we run `SELECT 1` within a second? If not, Kubernetes stops
  sending this pod traffic until the database is reachable again.
  """
  @impl true
  def ready? do
    # Migrations retry in the background after a DNS blip. Stay unready
    # until they have been applied, even if SELECT 1 would already succeed.
    CallRouter.Migrator.ready?() and database_responds?()
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  defp database_responds? do
    match?({:ok, _}, SQL.query(Repo, "SELECT 1", [], timeout: 1_000))
  end

  defp unavailable(e) do
    Logger.error("database unavailable: #{Exception.message(e)}")
    {:error, :unavailable}
  end
end
