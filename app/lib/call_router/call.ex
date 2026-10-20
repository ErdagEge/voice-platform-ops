defmodule CallRouter.Call do
  @moduledoc "Ecto schema for the `calls` table (see priv/repo/migrations)."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:call_id, :string, autogenerate: false}
  schema "calls" do
    field(:from, :string)
    field(:to, :string)
    field(:intent, :string)
    field(:queue, :string)
    field(:status, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @fields [:call_id, :from, :to, :intent, :queue, :status, :created_at]

  @doc "Build an insert changeset from the map produced by CallRouter.Routing."
  def changeset(call) do
    attrs = Map.update(call, :created_at, nil, &parse_time/1)

    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([:call_id, :from, :to, :queue, :status, :created_at])
  end

  @doc "Back to the plain map shape the API returns."
  def to_map(%__MODULE__{} = c) do
    %{
      call_id: c.call_id,
      from: c.from,
      to: c.to,
      intent: c.intent,
      queue: c.queue,
      status: c.status,
      created_at: DateTime.to_iso8601(c.created_at)
    }
  end

  defp parse_time(%DateTime{} = dt), do: dt

  defp parse_time(iso) when is_binary(iso) do
    {:ok, dt, 0} = DateTime.from_iso8601(iso)
    dt
  end
end
