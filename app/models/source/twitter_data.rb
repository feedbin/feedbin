class Source::TwitterData < Source

  def call
    twitter = TwitterFeed.new(@url, @config[:twitter_access_token], @config[:twitter_access_secret], @config[:twitter_screen_name])
    if twitter.feed
      feed = Feed.where(feed_url: twitter.url.to_s).take
      if !feed
        feed = Feed.create_from_parsed_feed(twitter.feed)
      end
      [feed]
    end
  end

end
