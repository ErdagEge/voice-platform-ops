defmodule CallRouter.Router do
  @moduledoc """
  HTTP routes. A Plug router is a pipeline: each `plug` below runs in order
  for every request, then the matching route handles it.
  """
  use Plug.Router
  require Logger

  alias CallRouter.{CallStore, Metrics, Routing}

  # Adds an x-request-id header and puts it in Logger metadata.
  plug(Plug.RequestId)
  # Our own logging/metrics hook (see below).
  plug(:observe)
  plug(:match)
  # Parse JSON bodies into conn.body_params.
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  # Liveness: "is the process alive?" Kubernetes restarts the pod if this fails.
  # Keep it dumb - no dependency checks, or a DB blip would cause restart loops.
  get "/healthz" do
    json(conn, 200, %{status: "ok"})
  end

  # Readiness: "can I serve traffic?" Kubernetes removes the pod from the
  # Service's endpoints while this fails (e.g. during startup or shutdown).
  get "/readyz" do
    if CallStore.ready?() do
      json(conn, 200, %{status: "ready"})
    else
      json(conn, 503, %{status: "not_ready"})
    end
  end

  post "/api/calls" do
    case Routing.route(conn.body_params) do
      {:ok, call} ->
        CallStore.put(call)
        Metrics.inc("call_router_calls_routed_total", %{queue: call.queue})
        Logger.info("call routed", call_id: call.call_id)
        json(conn, 201, call)

      {:error, reason} ->
        json(conn, 422, %{error: reason})
    end
  end

  get "/api/calls/:id" do
    case CallStore.get(id) do
      {:ok, call} -> json(conn, 200, call)
      :error -> json(conn, 404, %{error: "call not found"})
    end
  end

  # Prometheus scrapes this endpoint.
  get "/metrics" do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, Metrics.render())
  end

  match _ do
    json(conn, 404, %{error: "not found"})
  end

  # --- helpers -------------------------------------------------------------

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  # Registers a callback that runs right before the response is sent,
  # so we can log and count every request with its final status code.
  defp observe(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      ms = System.convert_time_unit(System.monotonic_time() - start, :native, :millisecond)

      Metrics.inc("http_requests_total", %{
        method: conn.method,
        status: conn.status
      })

      Logger.info("request",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: ms
      )

      conn
    end)
  end
end
