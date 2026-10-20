defmodule CallRouter.Router do
  @moduledoc """
  HTTP routes. A Plug router is a pipeline: each `plug` below runs in order
  for every request, then the matching route handles it.
  """
  use Plug.Router
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias CallRouter.{CallStore, FaultInjection, Routing, Tracing}

  # Adds an x-request-id header and puts it in Logger metadata.
  plug(Plug.RequestId)
  # Our own logging/metrics/tracing hook (see below).
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
    FaultInjection.maybe_delay()

    if FaultInjection.fail?() do
      error(:injected)
      Tracing.set_error("fault injection")

      conn
      |> assign(:fault_injected, true)
      |> json(503, %{error: "temporarily unavailable (fault injection)"})
    else
      route_call(conn)
    end
  end

  get "/api/calls/:id" do
    case CallStore.get(id) do
      {:ok, call} ->
        json(conn, 200, call)

      {:error, :not_found} ->
        json(conn, 404, %{error: "call not found"})

      {:error, :unavailable} ->
        error(:storage)
        json(conn, 503, %{error: "storage unavailable"})
    end
  end

  # Prometheus scrapes this endpoint.
  get "/metrics" do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, CallRouter.Telemetry.scrape())
  end

  match _ do
    json(conn, 404, %{error: "not found"})
  end

  # --- helpers -------------------------------------------------------------

  defp route_call(conn) do
    # Child spans make the steps of a request visible in the trace waterfall.
    decision = Tracer.with_span("routing.decide", do: Routing.route(conn.body_params))

    case decision do
      {:ok, call} ->
        case Tracer.with_span("call_store.put", do: CallStore.put(call)) do
          {:ok, call} ->
            :telemetry.execute([:call_router, :call, :routed], %{count: 1}, %{queue: call.queue})
            Tracing.set_attributes(%{"call.id": call.call_id, "call.queue": call.queue})
            Logger.info("call routed", call_id: call.call_id)
            json(conn, 201, call)

          {:error, :unavailable} ->
            # Counted twice on purpose: errors_total{kind="storage"} says *why*,
            # the 503 itself burns the availability error budget.
            error(:storage)
            json(conn, 503, %{error: "storage unavailable"})
        end

      {:error, reason} ->
        error(:validation)
        json(conn, 422, %{error: reason})
    end
  end

  defp error(kind), do: :telemetry.execute([:call_router, :error], %{count: 1}, %{kind: kind})

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  # Runs before routing. Registers a callback that fires right before the
  # response is sent, so we know the final status code and duration.
  defp observe(conn, _opts) do
    start = System.monotonic_time()
    Tracing.put_log_metadata()

    register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start
      route = route_template(conn)

      # Injected faults were already counted with their own kind.
      if conn.status >= 500 and !conn.assigns[:fault_injected] do
        error(:server)
        Tracing.set_error("HTTP #{conn.status}")
      end

      Tracing.name_server_span(conn.method, route)

      :telemetry.execute([:call_router, :http, :request], %{duration: duration}, %{
        method: conn.method,
        route: route,
        status: conn.status
      })

      Logger.info("request",
        method: conn.method,
        route: route,
        path: conn.request_path,
        status: conn.status,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond)
      )

      conn
    end)
  end

  # Plug.Router stores the matched route template ("/api/calls/:id") in
  # conn.private. The catch-all `match _` (template "/*_path") and requests
  # that never reached the router share one "unmatched" label.
  defp route_template(conn) do
    case conn.private do
      %{plug_route: {"/*_path", _fun}} -> "unmatched"
      %{plug_route: {route, _fun}} -> route
      _ -> "unmatched"
    end
  end
end
