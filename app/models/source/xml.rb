class Source::Xml < Source
  def find
    feed = create_from_request!(response)
    feeds.push(feed) if feed
  rescue Feedkit::NotFeed
  end
end
