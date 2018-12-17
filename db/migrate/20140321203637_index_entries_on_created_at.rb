class IndexEntriesOnCreatedAt < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def change
    add_index :entries, :created_at, order: {created_at: :desc}, algorithm: :concurrently
  end
end
