class AddSourceToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :source, :text
  end
end
