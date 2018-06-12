class AddOldPublicIdToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :old_public_id, :string
  end
end
