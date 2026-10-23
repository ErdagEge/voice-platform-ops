defmodule CallRouter.MigratorTest do
  use ExUnit.Case, async: false

  alias CallRouter.{CallStore, Migrator}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(CallRouter.Repo)
  end

  test "retries a failing database and then reports ready" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    name = unique_name()

    migrate = fn _repo ->
      n = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
      if n < 2, do: {:error, :nxdomain}, else: :ok
    end

    pid = start!(name, migrate)
    assert :ok = wait_until(fn -> GenServer.call(pid, :ready?) end)
    assert Agent.get(agent, & &1) >= 3
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "a raised nxdomain is retried instead of killing the process" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    migrate = fn _repo ->
      n = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

      if n < 1 do
        raise "tcp connect (call-router-db-rw.voice:5432): non-existing domain - :nxdomain"
      else
        :ok
      end
    end

    pid = start!(unique_name(), migrate)
    assert :ok = wait_until(fn -> GenServer.call(pid, :ready?) end)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "readiness stays closed while boot migrations are still retrying" do
    refute Process.whereis(Migrator)

    migrate = fn _repo -> {:error, :nxdomain} end
    pid = start!(Migrator, migrate)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    # The database answers, but the pod must not take traffic until migrations
    # have been applied. Stopping the retrier (migrations disabled) lifts the gate.
    refute CallStore.ready?()
    GenServer.stop(pid)
    assert CallStore.ready?()
  end

  defp start!(name, migrate) do
    {:ok, pid} =
      Migrator.start_link(repo: CallRouter.Repo, name: name, migrate: migrate, backoff_ms: 20)

    pid
  end

  defp unique_name, do: :"migrator_#{System.unique_integer([:positive])}"

  defp wait_until(fun, attempts \\ 50)

  defp wait_until(_fun, 0), do: flunk("timed out")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end
end
