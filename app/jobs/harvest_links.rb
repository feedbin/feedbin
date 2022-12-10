class HarvestLinks
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :network_default

  def perform(entry_id)
    entry = Entry.find(entry_id)
    tweets = [entry.tweet.main_tweet]
    tweets.push(entry.tweet.main_tweet.quoted_status) if entry.tweet.main_tweet.quoted_status?
    urls = find_urls(tweets)
    if url = urls.first
      page = MercuryParser.parse(url, nil, ENV["EXTRACT_USER_ALT"])
      entry.data["saved_pages"] = {url => page.to_h}
      entry.save!
      ImageCrawler::TwitterLinkImage.perform_async(entry.public_id, nil, url) if entry.tweet.link_tweet?
    end
    entry.content = ApplicationController.render template: "entries/_tweet_default", formats: :html, locals: {entry: entry}, layout: nil
    entry.save!
  rescue HTTP::TimeoutError, HTTP::ConnectionError
  end

  def find_urls(tweets)
    tweets.each_with_object([]) do |tweet, array|
      tweet.urls.each do |url|
        url = url.expanded_url
        if url_valid?(url)
          array.push(url.to_s)
        end
      end
    end
  end

  def url_valid?(url)
    !(url.host == "twitter.com")
  end
end
