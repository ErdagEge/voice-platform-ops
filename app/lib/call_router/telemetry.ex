defmodule CallRouter.Telemetry do
  @moduledoc """
  Metrics, the :telemetry way.

  1. Code *emits events* with `:telemetry.execute/3`, e.g.
     `[:call_router, :http, :request]` with a duration measurement.
  2. `metrics/0` *describes* which Prometheus metrics to build from them.
  3. `TelemetryMetricsPrometheus.Core` subscribes, aggregates in ETS, and
     `scrape/0` renders the Prometheus text format for GET /metrics.

  Exposed series:

    * `http_requests_total{method,route,status}`              counter
    * `http_request_duration_seconds_bucket{method,route,le}` histogram
    * `call_router_calls_routed_total{queue}`                 counter
    * `call_router_errors_total{kind}`                        counter
    * `call_router_db_up`                                     gauge (1/0)
    * `vm_memory_total_bytes`, `vm_run_queue_total`           gauges

  `route` is the *route template* (`/api/calls/:id`), never the raw path, so
  every call id doesn't create a new time series ("cardinality explosion").
  """
  use Supervisor
  import Telemetry.Metrics

  @reporter :call_router_prometheus

  # Latency buckets in seconds. Dense around our SLO thresholds (300 ms
  # p95 target, 500 ms "slow" limit) so percentiles there are accurate.
  @duration_buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0, 2.5, 5.0]

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus.Core, name: @reporter, metrics: metrics()},
      # Emits VM measurements every 10 s (used by the gauges below).
      {:telemetry_poller,
       name: :call_router_poller,
       period: :timer.seconds(10),
       measurements: [],
       vm_measurements: :default}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Prometheus text exposition of all metrics."
  def scrape, do: TelemetryMetricsPrometheus.Core.scrape(@reporter)

  @doc "Metric definitions (also handy to inspect in iex)."
  def metrics do
    [
      counter("http.requests.total",
        event_name: [:call_router, :http, :request],
        measurement: :duration,
        tags: [:method, :route, :status],
        description: "HTTP requests handled"
      ),
      distribution("http.request.duration.seconds",
        event_name: [:call_router, :http, :request],
        measurement: :duration,
        unit: {:native, :second},
        tags: [:method, :route],
        reporter_options: [buckets: @duration_buckets],
        description: "HTTP request latency"
      ),
      counter("call_router.calls.routed.total",
        event_name: [:call_router, :call, :routed],
        tags: [:queue],
        description: "Calls routed, by destination queue"
      ),
      counter("call_router.errors.total",
        event_name: [:call_router, :error],
        tags: [:kind],
        description: "Errors by kind (validation, injected, storage, server)"
      ),
      last_value("call_router.db.up",
        event_name: [:call_router, :db],
        measurement: :up,
        description: "1 if this pod can query PostgreSQL, else 0 (see CallRouter.DbHealth)"
      ),
      last_value("vm.memory.total.bytes",
        event_name: [:vm, :memory],
        measurement: :total,
        description: "BEAM memory in use"
      ),
      last_value("vm.run_queue.total",
        event_name: [:vm, :total_run_queue_lengths],
        measurement: :total,
        description: "Processes waiting to run (CPU saturation signal)"
      )
    ]
  end
end
