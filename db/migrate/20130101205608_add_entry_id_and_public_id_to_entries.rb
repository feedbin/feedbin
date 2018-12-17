class AddEntryIdAndPublicIdToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :entry_id, :string
    add_column :entries, :public_id, :string
    add_index :entries, :public_id, unique: true
  end
end
