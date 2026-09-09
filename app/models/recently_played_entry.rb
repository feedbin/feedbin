class RecentlyPlayedEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry, counter_cache: true

  # Bulk delete skips the counter cache, so the affected entries are repaired
  # afterwards. Without it every cleared row leaves its entry pinned against
  # EntryDeleter#prune_entries forever.
  def self.clear_for_user(user_id)
    entry_ids = where(user_id: user_id).pluck(:entry_id)
    where(user_id: user_id).delete_all
    EntryCounterRepair.enqueue(entry_ids)
  end
end
