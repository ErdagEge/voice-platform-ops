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
      {:jason, "~> 1.4"}
    ]
  end
end
