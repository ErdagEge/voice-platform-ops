defmodule CallRouter.Repo do
  @moduledoc "Ecto repository: the connection pool to PostgreSQL."
  use Ecto.Repo, otp_app: :call_router, adapter: Ecto.Adapters.Postgres
end
