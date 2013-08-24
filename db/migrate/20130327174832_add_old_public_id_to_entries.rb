class AddOldPublicIdToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :old_public_id, :string
  end
end
