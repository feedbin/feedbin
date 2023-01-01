class AddProviderParentIdToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :provider_parent_id, :text
  end
end
