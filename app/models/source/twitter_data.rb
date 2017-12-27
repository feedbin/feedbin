class Source::TwitterData < Source

  def call
    twitter_url = Feedkit::TwitterURLRecognizer.new(@url, @config[:twitter_screen_name])

    if twitter_url.valid?
      twitter = Feedkit::TwitterFeed.new(twitter_url, options[:twitter_access_token], options[:twitter_access_token])
      feed = Feed.where(feed_url: twitter.url.to_s).take
      if !feed
        feed = Feed.create_from_parsed_feed(twitter.feed)
      end
      [feed]
    end
  end

end
