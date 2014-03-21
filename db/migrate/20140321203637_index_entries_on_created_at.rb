class IndexEntriesOnCreatedAt < ActiveRecord::Migration
  disable_ddl_transaction!
  def change
    add_index :entries, :created_at, order: {created_at: :desc}, algorithm: :concurrently
  end
end
