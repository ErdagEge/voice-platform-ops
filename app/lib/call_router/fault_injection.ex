defmodule CallRouter.FaultInjection do
  @moduledoc """
  Deliberate failure for demos and chaos tests - OFF by default.

    * `FAULT_ERROR_RATE`  - 0.0..1.0, share of POST /api/calls answered with 503
    * `FAULT_LATENCY_MS`  - extra delay added to POST /api/calls

  Used to prove that alerts fire and dashboards react. Never enable in prod.
  """

  @doc "Sleep for the configured extra latency (no-op when 0)."
  def maybe_delay do
    case Application.get_env(:call_router, :fault_latency_ms, 0) do
      ms when is_integer(ms) and ms > 0 -> Process.sleep(ms)
      _ -> :ok
    end
  end

  @doc "True if this request should fail on purpose."
  def fail?, do: :rand.uniform() < Application.get_env(:call_router, :fault_error_rate, 0.0)
end
