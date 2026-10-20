defmodule CallRouter.Repo.Migrations.CreateCalls do
  use Ecto.Migration

  # Migrations are versioned schema changes. Ecto records which ones ran in
  # the `schema_migrations` table, so each runs exactly once per database.
  def change do
    create table(:calls, primary_key: false) do
      add(:call_id, :string, size: 32, primary_key: true)
      add(:from, :string, null: false)
      add(:to, :string, null: false)
      add(:intent, :string)
      add(:queue, :string, null: false)
      add(:status, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(index(:calls, [:created_at]))
  end
end
