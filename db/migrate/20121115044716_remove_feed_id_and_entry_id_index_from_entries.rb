class RemoveFeedIdAndEntryIdIndexFromEntries < ActiveRecord::Migration
  def up
# not exist for new installations
#    remove_index(:entries, name: :index_entries_on_feed_id_and_entry_id)
  end

  def down
  end
end
