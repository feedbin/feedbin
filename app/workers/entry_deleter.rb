class EntryDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(feed_id)
    feed = Feed.find(feed_id)
    unless feed.protected
      delete_entries(feed_id)
    end
  end

  def delete_entries(feed_id)
    entry_limit = 500
    entry_count = Entry.where(feed_id: feed_id).count
    if entry_count > entry_limit
      entries_to_keep = Entry.where(feed_id: feed_id).order('published DESC').limit(entry_limit).pluck('entries.id')
      entries_to_delete = Entry.select(:id, :public_id).where(feed_id: feed_id, starred_entries_count: 0).where.not(id: entries_to_keep)
      entries_to_delete_ids = entries_to_delete.map {|entry| entry.id }
      entries_to_delete_public_ids = entries_to_delete.map {|entry| entry.public_id }

      # Delete records
      UnreadEntry.where(entry_id: entries_to_delete_ids).delete_all
      entries_to_delete.delete_all

      entries_to_delete_ids.each do |entry_id|
        SearchIndexRemove.perform_async("Entry", entry_id)
      end

      Sidekiq.redis do |conn|
        conn.pipelined do
          entries_to_delete_public_ids.each do |public_id|
            conn.hdel("entry:public_ids:#{public_id[0..4]}", public_id)
          end
        end
      end

    end
  end

end
