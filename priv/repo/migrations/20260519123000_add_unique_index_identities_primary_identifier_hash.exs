defmodule AshyWalnutDesk.Repo.Migrations.AddUniqueIndexIdentitiesPrimaryIdentifierHash do
  use Ecto.Migration

  def change do
    create unique_index(:identities, [:primary_identifier_hash],
             name: "identities_primary_identifier_hash_index"
           )
  end
end
