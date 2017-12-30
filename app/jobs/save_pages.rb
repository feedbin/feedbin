class SavePages
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(entry_id)
    entry = Entry.find(entry_id)

    tweets = [entry.main_tweet]
    tweets.push(entry.main_tweet.quoted_status) if entry.main_tweet.quoted_status?

    urls = find_urls(tweets)

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

  def find_urls(tweets)
    tweets.each_with_object([]) do |tweet, array|
      tweet.urls.each do |url|
        url = url.expanded_url.to_s
        array.push(url) if url_valid?(url)
      end
    end
  end

  def url_valid?(url)
    url = URI.parse(url)
    if url.host == "twitter.com" && url.path.include?("/status/")
      false
    else
      true
    end
  end

end
