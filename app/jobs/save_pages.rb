class SavePages
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(entry_id)
    entry = Entry.find(entry_id)
    tweet = entry.tweet

    tweets = [tweet]
    tweets.push(tweet.retweeted_status) if tweet.retweeted_status?
    urls = tweets.each_with_object([]) do |tweet, array|
      tweet.urls.each do |url|
        array.push(url.expanded_url.to_s)
      end
    end

    saved_pages = urls.each_with_object({}) do |url, hash|
      key = FeedbinUtils.page_cache_key(url)
      begin
        hash[url] = Rails.cache.fetch(key) do
          Librato.increment 'readability.first_parse'
          MercuryParser.parse(url)
        end
      rescue
      end
    end
    entry.data["saved_pages"] = saved_pages
    entry.save!
  end

end
