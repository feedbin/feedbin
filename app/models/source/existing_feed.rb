class Source::ExistingFeed < Source
  def find
    if feed = Feed.xml.where(feed_url: response.url).take
      create_from_request!(response)
      feeds.push(feed.reload)
    end
  end
end
