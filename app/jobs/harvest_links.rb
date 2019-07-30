class HarvestLinks
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(entry_id)
    entry = Entry.find(entry_id)
    tweets = [entry.main_tweet]
    tweets.push(entry.main_tweet.quoted_status) if entry.main_tweet.quoted_status?
    urls = find_urls(tweets)
    if url = urls.first
      page = MercuryParser.parse(url)
      entry.data["saved_pages"] = {url => page.to_h}
      entry.save!
    end
    entry.content = ApplicationController.render template: "entries/_tweet_default.html.erb", locals: {entry: entry}, layout: nil
    entry.save!
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
