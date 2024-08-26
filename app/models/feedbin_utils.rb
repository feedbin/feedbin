class FeedbinUtils
  FEED_ENTRIES_PUBLISHED_KEY = "feed:%d:entry_ids:published"
  FEED_ENTRIES_CREATED_AT_KEY = "feed:%d:entry_ids:created_at"

  def self.update_public_id_cache(public_id, content, public_id_alt = nil)
    content_length = content.present? ? content.length : 0
    $redis[:refresher].with do |redis|
      redis.set(public_id, content_length)
    end
    if public_id_alt
      $redis[:refresher].with do |redis|
        redis.set(public_id_alt, content_length)
      end
    end
  end

  def self.public_id_exists?(public_id)
    $redis[:refresher].with do |redis|
      redis.exists?(public_id)
    end
  end

  def self.payment_details_key(user_id)
    "payment_details:%s:v5" % user_id
  end

  def self.shared_cache(key)
    hash = Sidekiq.redis do |redis|
      redis.hgetall key
    end
    hash.transform_keys(&:to_sym)
  end
  
  def self.key_value_parser(string, &block)
    (string || "").split("\s").map {_1.split("=")}.each_with_object({}) do |(item, weight), hash|
      hash[item] = yield(weight)
    end
  end
  
end
