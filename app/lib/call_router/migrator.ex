defmodule CallRouter.Migrator do
  @moduledoc """
  Applies Ecto migrations at boot, and retries until PostgreSQL is reachable.

  `Ecto.Migrator` as a supervision child runs the migrations inside `init/1`
  and returns `:ignore`. A connection error (chaos 03: DNS `:nxdomain` for
  the database Service while kube-proxy is still starting) crashes that
  init, so the application exits and kubelet CrashLoopBackOffs the pod.
  The backoff then grows to minutes, and the pod stays down after DNS has
  recovered until someone deletes it.

  This process returns immediately, keeps the BEAM up (`/healthz` stays
  green) and retries with exponential backoff. `/readyz` stays red until
  the migrations have been applied, so the pod takes no traffic early and
  becomes Ready on its own once DNS and the database answer.
  """
  use GenServer
  require Logger

  @min_backoff_ms 1_000
  @max_backoff_ms 30_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Whether boot migrations have finished.

  True when this process is not running (migrations disabled, or already
  applied before the node started). False when a retry is still in progress
  or the call times out because a migration attempt is blocked on the network.
  """
  def ready? do
    case Process.whereis(__MODULE__) do
      nil -> true
      pid -> GenServer.call(pid, :ready?, 1_000)
    end
  catch
    :exit, _ -> false
  end

  @impl true
  def init(opts) do
    state = %{
      repo: Keyword.fetch!(opts, :repo),
      migrate: Keyword.get(opts, :migrate, &migrate_repo/1),
      backoff: Keyword.get(opts, :backoff_ms, @min_backoff_ms),
      attempts: 0,
      ready: false
    }

    send(self(), :migrate)
    {:ok, state}
  end

  @impl true
  def handle_call(:ready?, _from, state), do: {:reply, state.ready, state}

  @impl true
  def handle_info(:migrate, %{ready: true} = state), do: {:noreply, state}

  def handle_info(:migrate, state) do
    case normalize(attempt(state)) do
      :ok ->
        Logger.info("database migrations applied after #{state.attempts} retries")
        {:noreply, %{state | ready: true}}

      {:error, reason} ->
        Logger.warning(
          "database migration attempt #{state.attempts + 1} failed (#{format_reason(reason)}); " <>
            "retrying in #{state.backoff}ms"
        )

        Process.send_after(self(), :migrate, state.backoff)
        {:noreply, %{state | attempts: state.attempts + 1, backoff: next_backoff(state.backoff)}}
    end
  end

  defp attempt(state) do
    state.migrate.(state.repo)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
  end

  defp migrate_repo(repo) do
    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
      {:ok, _, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(:ok), do: :ok
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(other), do: {:error, other}

  defp next_backoff(current), do: min(current * 2, @max_backoff_ms)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
