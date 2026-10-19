defmodule CallRouter.RouterTest do
  # async: false because the ETS tables are shared global state.
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias CallRouter.Router

  @opts Router.init([])

  defp call(conn), do: Router.call(conn, @opts)
  defp body(conn), do: Jason.decode!(conn.resp_body)

  defp post_json(path, payload) do
    conn(:post, path, Jason.encode!(payload))
    |> put_req_header("content-type", "application/json")
    |> call()
  end

  test "GET /healthz returns ok" do
    conn = conn(:get, "/healthz") |> call()
    assert conn.status == 200
    assert body(conn) == %{"status" => "ok"}
  end

  test "GET /readyz returns ready" do
    conn = conn(:get, "/readyz") |> call()
    assert conn.status == 200
    assert body(conn)["status"] == "ready"
  end

  describe "POST /api/calls" do
    for {intent, queue} <- [{"buy", "sales"}, {"support", "support"}, {"weather", "voicebot"}] do
      test "routes intent #{intent} to #{queue}" do
        conn = post_json("/api/calls", %{from: "+3211", to: "+3222", intent: unquote(intent)})
        assert conn.status == 201
        assert %{"queue" => unquote(queue), "call_id" => id} = body(conn)
        assert byte_size(id) == 32
      end
    end

    test "missing intent defaults to voicebot" do
      conn = post_json("/api/calls", %{from: "+3211", to: "+3222"})
      assert body(conn)["queue"] == "voicebot"
    end

    test "rejects missing fields with 422" do
      conn = post_json("/api/calls", %{intent: "buy"})
      assert conn.status == 422
      assert body(conn)["error"] =~ "required"
    end
  end

  describe "GET /api/calls/:id" do
    test "returns a stored call" do
      %{"call_id" => id} =
        post_json("/api/calls", %{from: "a", to: "b", intent: "help"}) |> body()

      conn = conn(:get, "/api/calls/#{id}") |> call()
      assert conn.status == 200
      assert %{"call_id" => ^id, "queue" => "support", "from" => "a"} = body(conn)
    end

    test "returns 404 for unknown id" do
      conn = conn(:get, "/api/calls/nope") |> call()
      assert conn.status == 404
    end
  end

  describe "GET /metrics" do
    test "exposes request counters labelled by route template" do
      %{"call_id" => id} = post_json("/api/calls", %{from: "a", to: "b", intent: "buy"}) |> body()
      conn(:get, "/api/calls/#{id}") |> call()

      conn = conn(:get, "/metrics") |> call()
      assert conn.status == 200
      assert [ctype | _] = get_resp_header(conn, "content-type")
      assert ctype =~ "text/plain"

      assert conn.resp_body =~ ~s(call_router_calls_routed_total{queue="sales"})

      assert conn.resp_body =~
               ~s(http_requests_total{method="POST",route="/api/calls",status="201"})

      # The template, not the real id - keeps metric cardinality bounded.
      assert conn.resp_body =~ ~s(route="/api/calls/:id")
      refute conn.resp_body =~ id
    end

    test "exposes a latency histogram with SLO-friendly buckets" do
      conn(:get, "/healthz") |> call()
      metrics = (conn(:get, "/metrics") |> call()).resp_body

      assert metrics =~ "# TYPE http_request_duration_seconds histogram"

      for le <- ["0.3", "0.5", "+Inf"] do
        assert metrics =~
                 ~s(http_request_duration_seconds_bucket{method="GET",route="/healthz",le="#{le}"})
      end

      assert metrics =~ "http_request_duration_seconds_count"
      assert metrics =~ "http_request_duration_seconds_sum"
    end

    test "counts validation errors" do
      post_json("/api/calls", %{})
      metrics = (conn(:get, "/metrics") |> call()).resp_body
      assert metrics =~ ~s(call_router_errors_total{kind="validation"})
    end

    test "unknown routes share one label" do
      conn(:get, "/does/not/exist/123") |> call()
      metrics = (conn(:get, "/metrics") |> call()).resp_body
      assert metrics =~ ~s(route="unmatched")
      refute metrics =~ "/does/not/exist"
    end
  end

  describe "fault injection" do
    setup do
      on_exit(fn -> Application.put_env(:call_router, :fault_error_rate, 0.0) end)
    end

    test "returns 503 and counts an injected error when enabled" do
      Application.put_env(:call_router, :fault_error_rate, 1.0)
      conn = post_json("/api/calls", %{from: "a", to: "b", intent: "buy"})
      assert conn.status == 503

      metrics = (conn(:get, "/metrics") |> call()).resp_body
      assert metrics =~ ~s(call_router_errors_total{kind="injected"})
    end

    test "is off by default" do
      assert post_json("/api/calls", %{from: "a", to: "b"}).status == 201
    end
  end

  test "unknown route returns 404" do
    assert (conn(:get, "/nope") |> call()).status == 404
  end
end
