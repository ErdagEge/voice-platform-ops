defmodule CallRouter.MixProject do
  use Mix.Project

  def project do
    [
      app: :call_router,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # `mod:` tells the BEAM which module starts our supervision tree.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {CallRouter.Application, []}
    ]
  end

  # `mix release` bundles our compiled code, its deps and the Erlang runtime
  # (ERTS) into a self-contained folder - no Elixir install needed to run it.
  defp releases do
    [
      call_router: [
        include_executables_for: [:unix],
        # OpenTelemetry docs: start the exporter before the SDK, and make the
        # SDK :temporary so a tracing failure can never take the app down.
        applications: [opentelemetry_exporter: :permanent, opentelemetry: :temporary],
        # Strip debug info from .beam files to shrink the release.
        strip_beams: true
      ]
    ]
  end

  defp deps do
    [
      # Bandit is the HTTP server (accepts TCP connections, speaks HTTP).
      {:bandit, "~> 1.5"},
      # Plug is the request/response abstraction + router DSL.
      {:plug, "~> 1.16"},
      # Jason encodes/decodes JSON.
      {:jason, "~> 1.4"},
      # --- Metrics ---------------------------------------------------------
      # :telemetry is the standard Erlang/Elixir event bus: code emits events,
      # reporters subscribe. telemetry_metrics describes metrics (counter,
      # histogram...) and the Prometheus "core" reporter aggregates them and
      # renders the /metrics text format.
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      # Periodically emits BEAM VM measurements (memory, run queues).
      {:telemetry_poller, "~> 1.1"},
      # --- Tracing (OpenTelemetry) -----------------------------------------
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      # Creates a server span for every HTTP request handled by Bandit.
      {:opentelemetry_bandit, "~> 0.3"},
      # Static code analysis / style linter (dev & test only, not in the release).
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
