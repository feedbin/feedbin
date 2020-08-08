class Source::MetaLinks < Source
  def find
    return unless document?

    urls = document.css("link[rel=alternate]").each_with_object([]) do |link, array|
      if link_valid?(link)
        array.push join_url(response.url, link["href"])
      end
    end

    urls.uniq.each do |url|
      feeds.push(create_from_url!(url))
    rescue Feedkit::Error
    end
  end

  private

  def link_valid?(link)
    valid = false
    types = ["application/rss+xml", "application/atom+xml", "application/json"]
    if link["type"] && link["href"]
      type = link["type"].strip.downcase
      valid = types.include?(type)
    end
    valid
  end
end
