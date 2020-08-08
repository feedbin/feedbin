class Source::ExistingFeed < Source
  def find
    if feed = Feed.xml.where(feed_url: response.url).take
      feeds.push(feed)
    end
  end
end
