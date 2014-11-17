class FeedbinUtils
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
    "feed:%d:entry_ids:created_at" % feed_id
  end
end
