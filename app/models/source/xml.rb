class Source::Xml < Source
  def find
    feeds.push(create_from_request!(response))
  rescue Feedkit::NotFeed
  end
end
