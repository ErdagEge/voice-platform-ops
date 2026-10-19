defmodule CallRouter.Tracing do
  @moduledoc """
  Small helpers around OpenTelemetry.

  A *trace* is the story of one request; it is made of *spans* (timed steps).
  `opentelemetry_bandit` opens the server span for each HTTP request; here we
  give it a readable name, add attributes, and copy the trace id into Logger
  metadata so every log line can be matched to its trace in Grafana.

  When no OTLP endpoint is configured the SDK still creates ids, but the
  exporter is `:none`, so nothing is sent anywhere (tests, CI, local dev).
  """
  require OpenTelemetry.Tracer, as: Tracer

  @doc "Copy the current trace/span ids into Logger metadata (if a span is active)."
  def put_log_metadata do
    case Tracer.current_span_ctx() do
      :undefined ->
        :ok

      span_ctx ->
        trace_id = :otel_span.hex_trace_id(span_ctx)

        # An all-zero / empty id means "no real span" (non-recording context).
        if trace_id not in ["", "00000000000000000000000000000000"] do
          Logger.metadata(trace_id: trace_id, span_id: :otel_span.hex_span_id(span_ctx))
        end

        :ok
    end
  end

  @doc "Name the HTTP server span after the route template, e.g. `POST /api/calls`."
  def name_server_span(method, route) do
    Tracer.update_name("#{method} #{route}")
    Tracer.set_attribute(:"http.route", route)
  end

  @doc "Set attributes on the current span."
  def set_attributes(attrs), do: Tracer.set_attributes(attrs)

  @doc "Mark the current span as failed."
  def set_error(message), do: Tracer.set_status(OpenTelemetry.status(:error, message))
end
