class RemoveFeedIdAndEntryIdIndexFromEntries < ActiveRecord::Migration[4.2]
  def up
    if index_name_exists?(:entries, :index_entries_on_feed_id_and_entry_id)
      remove_index :entries, name: :index_entries_on_feed_id_and_entry_id
    end
  end

  def down
  end
end
