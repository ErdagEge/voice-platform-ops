defmodule CallRouter.LogFormatter do
  @moduledoc """
  Formats Logger events as one JSON object per line, e.g.

      {"time":"...","level":"info","msg":"request","method":"GET","status":200}
  """

  def format(level, message, timestamp, metadata) do
    base = %{
      time: format_time(timestamp),
      level: level,
      msg: IO.chardata_to_string(message)
    }

    fields = Map.new(metadata, fn {k, v} -> {k, safe(v)} end)
    [Jason.encode!(Map.merge(fields, base)), "\n"]
  rescue
    # A logger must never crash the app; fall back to plain text.
    _ -> "#{inspect({level, message, metadata})}\n"
  end

  defp format_time({{y, mo, d}, {h, mi, s, ms}}) do
    NaiveDateTime.new!(y, mo, d, h, mi, s, {ms * 1000, 3}) |> NaiveDateTime.to_iso8601()
  end

  defp safe(v) when is_binary(v) or is_number(v) or is_atom(v), do: v
  defp safe(v), do: inspect(v)
end
