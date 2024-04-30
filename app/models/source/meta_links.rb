class Source::MetaLinks < Source
  def options
    return unless document?

    document.css("link[rel~=alternate]").each_with_object([]) do |link, array|
      if link_valid?(link)
        array.push join_url(response.url, link["href"])
      end
    end
  end

  def find
    options.uniq.each do |url|
      feed = create_from_url!(url)
      feeds.push(feed) if feed
    rescue Feedkit::Error
    end
  end

  private

  def link_valid?(link)
    valid = false
    types = ["application/rss+xml", "application/atom+xml", "application/feed+json", "application/json"]
    if link["type"] && link["href"]
      type = link["type"].strip.downcase
      valid = types.include?(type)
    end
    valid
  end
end
