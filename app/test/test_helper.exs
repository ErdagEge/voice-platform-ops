ExUnit.start()
# Each test checks out its own DB connection inside a transaction that is
# rolled back afterwards (shared mode: the router runs in the test process).
Ecto.Adapters.SQL.Sandbox.mode(CallRouter.Repo, :manual)
