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
      UpdatedEntry.where(entry_id: entries_to_delete_ids).delete_all
      RecentlyReadEntry.where(entry_id: entries_to_delete_ids).delete_all
      entries_to_delete.delete_all

      Sidekiq.redis do |conn|
        conn.pipelined do
          entries_to_delete_public_ids.each do |public_id|
            key = FeedbinUtils.public_id_key(public_id)
            conn.hdel(key, public_id)
          end
        end
      end

      key_created_at = FeedbinUtils.redis_feed_entries_created_at_key(feed_id)
      key_published = FeedbinUtils.redis_feed_entries_published_key(feed_id)
      if entries_to_delete_ids.present?
        SearchIndexRemove.perform_async(entries_to_delete_ids)
        $redis.zrem(key_created_at, entries_to_delete_ids)
        $redis.zrem(key_published, entries_to_delete_ids)
      end

      Librato.increment('entry.destroy', by: entries_to_delete_ids.count)

    end
  end

end
