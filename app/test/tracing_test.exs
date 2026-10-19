defmodule CallRouter.TracingTest do
  use ExUnit.Case, async: false
  require OpenTelemetry.Tracer, as: Tracer

  alias CallRouter.{LogFormatter, Tracing}

  setup do
    on_exit(fn -> Logger.reset_metadata() end)
  end

  test "copies the active trace and span ids into Logger metadata" do
    Tracer.with_span "test-span" do
      Tracing.put_log_metadata()
      meta = Logger.metadata()

      assert meta[:trace_id] =~ ~r/^[0-9a-f]{32}$/
      assert meta[:span_id] =~ ~r/^[0-9a-f]{16}$/
      assert meta[:trace_id] == :otel_span.hex_trace_id(Tracer.current_span_ctx())
    end
  end

  test "is a no-op without an active span" do
    Logger.reset_metadata()
    assert :ok = Tracing.put_log_metadata()
    refute Keyword.has_key?(Logger.metadata(), :trace_id)
  end

  test "JSON log lines carry the trace_id field" do
    line =
      LogFormatter.format(:info, "hello", {{2026, 1, 1}, {0, 0, 0, 0}}, trace_id: "abc123")
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert line["trace_id"] == "abc123"
    assert line["msg"] == "hello"
  end
end
