class ParsedXMLFeed < ParsedFeed

  def feed
    @feed ||= Feedjira::Feed.parse(@body)
  rescue ArgumentError
    if @feed_request.charset
      @feed ||= Feedjira::Feed.parse(@body.force_encoding(@feed_request.charset))
    else
      @feed ||= Feedjira::Feed.parse(@body.force_encoding("ASCII-8BIT"))
    end
  end

  def title
    @title ||= feed.title ? feed.title.strip : "(No title)"
  end

  def site_url
    @site_url ||= begin
      if feed.url
        url = feed.url
      else
        if feed_url =~ /feedburner\.com/
          url = last_effective_url(feed.entries.first.url)
          url = url_from_host(url)
        else
          url = url_from_host(feed_url)
        end
      end
      url
    end
  end

  def self_url
    @self_url ||= begin
      url = feed_url
      if feed.self_url
        url = feed.self_url.strip
        if !url.match(/^http/)
          url = URI.join(feed_url, url).to_s
        end
      end
      url
    rescue
      feed_url
    end
  end

  def hubs
    @hubs = feed.respond_to?(:hubs) ? feed.hubs : []
  end

  def entries
    @entries ||= begin
      entries = []
      if feed.entries.respond_to?(:any?) && feed.entries.any?
        entries = feed.entries.map do |entry|
          ParsedXMLEntry.new(entry, base_url)
        end
        entries = entries.uniq { |entry| entry.public_id }
      end
      entries
    end
  end

end
