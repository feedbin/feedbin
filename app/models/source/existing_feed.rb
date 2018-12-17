class Source::ExistingFeed < Source
  def call
    feed = Feed.xml.where(feed_url: @url).take
    if feed
      @feed_options.push(FeedOption.new(feed.feed_url, feed.feed_url, feed.title, "existing_feed"))
    end
    create_feeds!
  end
end
