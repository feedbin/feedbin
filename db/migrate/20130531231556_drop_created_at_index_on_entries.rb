class DropCreatedAtIndexOnEntries < ActiveRecord::Migration
  def self.up
    remove_index :entries, :created_at
  end

  def self.down
    add_index :entries, :created_at, algorithm: :concurrently
  end
end
