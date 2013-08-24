class AddEntryIdAndPublicIdToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :entry_id, :string
    add_column :entries, :public_id, :string
    add_index  :entries, :public_id, unique: true
  end
end
