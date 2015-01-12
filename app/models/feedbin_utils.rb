class FeedbinUtils

  FEED_ENTRIES_PUBLISHED_KEY = "feed:%d:entry_ids:published"
  FEED_ENTRIES_CREATED_AT_KEY = "feed:%d:entry_ids:created_at"

  def self.update_public_id_cache(public_id, content)
    content_length = (content.present?) ? content.length : 1
    key = public_id_key(public_id)
    Sidekiq.redis do |client|
      client.hset(key, public_id, content_length)
    end
  end

  def self.public_id_key(public_id)
    "entry:public_ids:%s" % public_id[0..4]
  end

  def self.redis_feed_entries_created_at_key(feed_id)
    FEED_ENTRIES_CREATED_AT_KEY % feed_id
  end

  def self.redis_feed_entries_published_key(feed_id)
    FEED_ENTRIES_PUBLISHED_KEY % feed_id
  end

  def self.redis_user_entries_published_key(user_id)
    "user:%d:sorted_entry_ids:published:v2" % user_id
  end
end
