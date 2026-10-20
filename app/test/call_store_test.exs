defmodule CallRouter.CallStoreTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL.Sandbox

  alias CallRouter.{CallStore, Repo, Routing}

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp new_call do
    {:ok, call} = Routing.route(%{"from" => "+3247", "to" => "+3280", "intent" => "buy"})
    call
  end

  describe "Postgres store (the default in tests)" do
    test "put/get round-trips the API shape" do
      call = new_call()
      assert {:ok, stored} = CallStore.put(call)
      assert {:ok, ^stored} = CallStore.get(call.call_id)
      assert stored.queue == "sales"
      assert {:ok, _, 0} = DateTime.from_iso8601(stored.created_at)
    end

    test "unknown id is :not_found" do
      assert {:error, :not_found} = CallStore.get("does-not-exist")
    end

    test "is ready when the database answers" do
      assert CallStore.ready?()
    end
  end

  describe "Memory store (fallback without DATABASE_URL)" do
    alias CallRouter.CallStore.Memory

    setup do
      start_supervised!(Memory)
      :ok
    end

    test "put/get and readiness" do
      call = new_call()
      assert {:ok, ^call} = Memory.put(call)
      assert {:ok, ^call} = Memory.get(call.call_id)
      assert {:error, :not_found} = Memory.get("nope")
      assert Memory.ready?()
    end
  end
end
