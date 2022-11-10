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

  def self.escape_search(query)
    if query.present? && query.respond_to?(:gsub)
      special_characters_regex = /([\+\-\!\{\}\[\]\^\~\?\\\/])/
      escape = '\ '.sub(" ", "")
      query = query.gsub(special_characters_regex) { |character| escape + character }

      query = query.gsub("title_exact:", "title.exact:")
      query = query.gsub("content_exact:", "content.exact:")
      query = query.gsub("body:", "content:")
      query = query.gsub("emoji:", "")
      query = query.gsub("_missing_:", "NOT _exists_:")

      colon_regex = /(?<!title|title.exact|feed_id|content|content.exact|author|_missing_|_exists_|twitter_screen_name|twitter_name|twitter_retweet|twitter_media|twitter_image|twitter_link|emoji|url|url.exact|link|type):(?=.*)/
      query = query.gsub(colon_regex, '\:')
      query
    end
  end

  def self.shared_cache(key)
    hash = Sidekiq.redis do |redis|
      redis.hgetall key
    end
    hash.transform_keys(&:to_sym)
  end
end
