class Source::BodyLinks < Source

  def options
    return unless document?

    urls = document.css("a").each_with_object([]) do |anchor, array|
      if is_candidate?(anchor)
        array.push join_url(response.url, anchor["href"])
      end
    end

    urls.first(4)
  end

  def find
    options.each do |url|
      feed = create_from_url!(url)
      feeds.push(feed) if feed
    rescue Feedkit::Error
    end
  end

  private

  def is_candidate?(anchor)
    types = ["feed", "xml", "rss", "atom"]
    anchor["href"] && types.any? { |type| anchor["href"].include?(type) }
  end
end
