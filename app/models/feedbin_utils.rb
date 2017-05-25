class FeedbinUtils

  FEED_ENTRIES_PUBLISHED_KEY = "feed:%d:entry_ids:published"
  FEED_ENTRIES_CREATED_AT_KEY = "feed:%d:entry_ids:created_at"

  def self.update_public_id_cache(public_id, content, public_id_alt = nil)
    content_length = (content.present?) ? content.length : 1
    $redis[:id_cache].set(public_id, content_length)
    if public_id_alt
      $redis[:id_cache].set(public_id_alt, content_length)
    end
  end

  def self.public_id_exists?(public_id)
    $redis[:id_cache].exists(public_id)
  end

  def self.redis_feed_entries_created_at_key(feed_id)
    FEED_ENTRIES_CREATED_AT_KEY % feed_id
  end

  def self.redis_feed_entries_published_key(feed_id)
    FEED_ENTRIES_PUBLISHED_KEY % feed_id
  end

  def self.redis_user_entries_published_key(user_id, feed_ids)
    feed_key = feed_ids.sort.join
    feed_key = Digest::SHA1.hexdigest(feed_key)
    "user:%d:feed_key:%s:entry_ids:published" % [user_id, feed_key]
  end

end
