defmodule CallRouter.MixProject do
  use Mix.Project

  def project do
    [
      app: :call_router,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # `mod:` tells the BEAM which module starts our supervision tree.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {CallRouter.Application, []}
    ]
  end

  defp deps do
    [
      # Bandit is the HTTP server (accepts TCP connections, speaks HTTP).
      {:bandit, "~> 1.5"},
      # Plug is the request/response abstraction + router DSL.
      {:plug, "~> 1.16"},
      # Jason encodes/decodes JSON.
      {:jason, "~> 1.4"}
    ]
  end
end
