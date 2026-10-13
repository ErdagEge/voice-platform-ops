defmodule CallRouter.Metrics do
  @moduledoc """
  Tiny dependency-free metrics registry, rendered in Prometheus text format.

  Counters live in ETS so concurrent requests can increment them atomically.
  Later steps may swap this for `telemetry_metrics_prometheus_core`; the
  /metrics output format will stay Prometheus-compatible either way.
  """
  use GenServer

  @table :call_router_metrics

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Increment a counter identified by name + label map."
  def inc(name, labels \\ %{}) do
    :ets.update_counter(@table, {name, labels}, 1, {{name, labels}, 0})
  end

  @doc "Render all counters as Prometheus exposition text."
  def render do
    @table
    |> :ets.tab2list()
    |> Enum.sort()
    |> Enum.map_join(fn {{name, labels}, value} ->
      "#{name}#{format_labels(labels)} #{value}\n"
    end)
  end

  defp format_labels(labels) when map_size(labels) == 0, do: ""

  defp format_labels(labels) do
    inner = labels |> Enum.sort() |> Enum.map_join(",", fn {k, v} -> ~s(#{k}="#{v}") end)
    "{#{inner}}"
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, nil}
  end
end
