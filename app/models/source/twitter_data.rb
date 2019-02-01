class Source::TwitterData < Source
  def call
    recognized_url = Feedkit::TwitterURLRecognizer.new(@url, @config[:twitter_screen_name])
    if recognized_url.valid?
      twitter = Feedkit::Tweets.new(recognized_url, @config[:twitter_access_token], @config[:twitter_access_secret])
      feed = Feed.where(feed_url: recognized_url.url.to_s).take
      feed ||= Feed.create_from_parsed_feed(twitter.feed)
      [feed]
    end
  end
end
