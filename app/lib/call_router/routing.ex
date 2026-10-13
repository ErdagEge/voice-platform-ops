defmodule CallRouter.Routing do
  @moduledoc """
  Pure business logic: decide which queue a call goes to.

  Keeping this free of HTTP concerns makes it trivial to unit test.
  """

  @intent_queues %{
    "buy" => "sales",
    "pricing" => "sales",
    "sales" => "sales",
    "help" => "support",
    "support" => "support",
    "billing" => "support",
    "complaint" => "support"
  }

  @doc """
  Validate params and build a routing decision.

  Unknown intents fall back to the automated `voicebot` queue.
  """
  def route(%{"from" => from, "to" => to} = params)
      when is_binary(from) and is_binary(to) and from != "" and to != "" do
    intent = params |> Map.get("intent", "") |> to_string() |> String.downcase()

    {:ok,
     %{
       call_id: generate_id(),
       from: from,
       to: to,
       intent: intent,
       queue: Map.get(@intent_queues, intent, "voicebot"),
       status: "routed",
       created_at: DateTime.utc_now() |> DateTime.to_iso8601()
     }}
  end

  def route(_), do: {:error, "fields 'from' and 'to' are required non-empty strings"}

  # 16 random bytes, hex encoded -> 32 char unguessable id.
  defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
