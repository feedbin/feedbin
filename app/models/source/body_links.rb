class Source::BodyLinks < Source
  def find
    return unless document?

    urls = document.css("a").each_with_object([]) do |anchor, array|
      if is_candidate?(anchor)
        array.push join_url(response.url, anchor["href"])
      end
    end

    urls.first(4).each do |url|
      feeds.push(create_from_url!(url))
    rescue Feedkit::Error
    end
  end

  private

  def is_candidate?(anchor)
    types = ["feed", "xml", "rss", "atom"]
    anchor["href"] && types.any? { |type| anchor["href"].include?(type) }
  end
end
