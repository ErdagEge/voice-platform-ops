defmodule CallRouter.Release do
  @moduledoc """
  Tasks for the release, where `mix` is not available. Run from a pod:

      bin/call_router eval "CallRouter.Release.migrate()"

  (Migrations also run automatically at boot - see CallRouter.CallStore.)
  """
  @app :call_router

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
