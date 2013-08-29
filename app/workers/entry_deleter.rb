class EntryDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(feed_id)
    entry_limit = 500
    entry_count = Entry.where(feed_id: feed_id).count
    if entry_count > entry_limit
      entries_to_keep = Entry.where(feed_id: feed_id).order('published DESC').limit(entry_limit).pluck('entries.id')
      entries_to_delete = Entry.select(:id).where(feed_id: feed_id, starred_entries_count: 0).where.not(id: entries_to_keep)
      entries_to_delete_ids = entries_to_delete.map {|entry| entry.id }

      # Delete records
      UnreadEntry.where(entry_id: entries_to_delete_ids).delete_all
      entries_to_delete.delete_all
    end
  end

end
