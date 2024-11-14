class Source::ExistingFeed < Source
  def find
    if feed = Feed.xml.where(feed_url: response.url).take
      response.parse # check if it's actually a feed
      feeds.push(feed)
    end
  end
end
