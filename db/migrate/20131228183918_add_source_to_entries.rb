class AddSourceToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :source, :text
  end
end
