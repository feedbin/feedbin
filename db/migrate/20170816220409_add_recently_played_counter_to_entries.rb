class AddRecentlyPlayedCounterToEntries < ActiveRecord::Migration[5.0]
  disable_ddl_transaction!

  def up
    add_column :entries, :recently_played_entries_count, :integer
    add_index :entries, :recently_played_entries_count, algorithm: :concurrently
    change_column_default :entries, :recently_played_entries_count, 0

    UpdateDefaultColumn.perform_async({
      "klass" => "Entry",
      "column" => "recently_played_entries_count",
      "default" => 0,
      "schedule" => true,
    })
  end

  def down
    remove_column :entries, :recently_played_entries_count
  end
end
