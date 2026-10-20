defmodule CallRouter.StorageOutageTest do
  @moduledoc "What the API does when the database is gone."
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias CallRouter.Router

  # A store that behaves like an unreachable database.
  defmodule DownStore do
    @behaviour CallRouter.CallStore
    def put(_call), do: {:error, :unavailable}
    def get(_id), do: {:error, :unavailable}
    def ready?, do: false
  end

  @opts Router.init([])

  setup do
    previous = Application.get_env(:call_router, :store)
    Application.put_env(:call_router, :store, DownStore)
    on_exit(fn -> Application.put_env(:call_router, :store, previous) end)
  end

  defp call(conn), do: Router.call(conn, @opts)

  test "readiness fails so Kubernetes stops routing traffic to the pod" do
    assert (conn(:get, "/readyz") |> call()).status == 503
  end

  test "liveness stays OK - a DB outage must not restart the pods" do
    assert (conn(:get, "/healthz") |> call()).status == 200
  end

  test "POST and GET answer 503 and count a storage error" do
    conn =
      conn(:post, "/api/calls", Jason.encode!(%{from: "a", to: "b"}))
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 503
    assert (conn(:get, "/api/calls/abc") |> call()).status == 503

    metrics = (conn(:get, "/metrics") |> call()).resp_body
    assert metrics =~ ~s(call_router_errors_total{kind="storage"})
  end
end
