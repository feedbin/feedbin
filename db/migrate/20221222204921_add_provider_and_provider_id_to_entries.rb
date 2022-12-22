class AddProviderAndProviderIdToEntries < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :entries, :provider, :bigint
    add_column :entries, :provider_id, :text
    add_index :entries, [:provider, :provider_id], where: "provider IS NOT NULL AND provider_id IS NOT NULL", algorithm: :concurrently
  end
end
