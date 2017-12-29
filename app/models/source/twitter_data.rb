class Source::TwitterData < Source

  def call
    twitter_url = Feedkit::TwitterURLRecognizer.new(@url, @config[:twitter_screen_name])
    if twitter_url.valid?
      twitter = Feedkit::Tweets.new(twitter_url, @config[:twitter_access_token], @config[:twitter_access_secret])
      feed = Feed.where(feed_url: twitter.url.to_s).take
      if !feed
        feed = Feed.create_from_parsed_feed(twitter.feed)
      end
      [feed]
    end
  end

end
