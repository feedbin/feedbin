class EntryDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(feed_id)
    feed = Feed.find(feed_id)

    entry_limit = if ENV["ENTRY_LIMIT"]
      ENV["ENTRY_LIMIT"].to_i
    else
      feed.subscriptions_count == 0 ? 10 : 400
    end

    feed.feed_stats.where("day < ?", 40.days.ago).delete_all
    unless feed.protected
      delete_entries(feed_id, entry_limit)
    end
  end

  def delete_entries(feed_id, entry_limit)
    entry_count = Entry.where(feed_id: feed_id).count
    if entry_count > entry_limit
      entries_to_keep = Entry.where(feed_id: feed_id).order("published DESC").limit(entry_limit).pluck("entries.id")
      entries_to_delete = Entry.where(feed_id: feed_id, starred_entries_count: 0, recently_played_entries_count: 0).where.not(id: entries_to_keep).pluck(:id, :image)
      entries_to_delete_ids = entries_to_delete.map(&:first)
      entries_to_delete_images = entries_to_delete.map { |array| array.last && array.last["processed_url"] }.compact

      # Delete records
      UnreadEntry.where(entry_id: entries_to_delete_ids).delete_all
      UpdatedEntry.where(entry_id: entries_to_delete_ids).delete_all
      RecentlyReadEntry.where(entry_id: entries_to_delete_ids).delete_all
      Entry.where(id: entries_to_delete_ids).delete_all

      if entries_to_delete_images.present?
        ImageDeleter.perform_async(entries_to_delete_images)
      end

      if entries_to_delete_ids.present?
        key_created_at = FeedbinUtils.redis_created_at_key(feed_id)
        key_published = FeedbinUtils.redis_published_key(feed_id)
        SearchIndexRemove.perform_async(entries_to_delete_ids)
        $redis[:entries].with do |redis|
          redis.zrem(key_created_at, entries_to_delete_ids)
          redis.zrem(key_published, entries_to_delete_ids)
        end
      end
      Librato.increment("entry.destroy", by: entries_to_delete_ids.count)
    end
  end
end
