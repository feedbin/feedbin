class RemoveFeedIdIndexFromEntries < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    remove_index :entries, :feed_id, algorithm: :concurrently
  end

  def down
    add_index :entries, :feed_id, algorithm: :concurrently
  end
end
