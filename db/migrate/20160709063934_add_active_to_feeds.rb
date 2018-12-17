class AddActiveToFeeds < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    add_column :feeds, :active, :boolean
    change_column_default(:feeds, :active, true)
    add_index :feeds, :active, algorithm: :concurrently
  end

  def down
    remove_column :feeds, :active
  end
end
