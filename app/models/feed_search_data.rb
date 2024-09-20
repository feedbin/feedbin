class FeedSearchData
  EXCLUDE = ["", "http:", "https:", "com", "net", "co", "index", "rss", "xml", "www", "org", "de", "me"]
  def initialize(feed)
    @feed = feed
  end

  def to_h
    {}.tap do |hash|
      hash[:id]                  = @feed.id
      hash[:title]               = @feed.title&.to_plain_text
      hash[:site_url]            = format_url(@feed.site_url)
      hash[:feed_url]            = format_url(@feed.self_url || @feed.feed_url)
      hash[:self_url]            = @feed.self_url
      hash[:description]         = description
      hash[:meta_title]          = @feed.meta_title
      hash[:meta_description]    = @feed.meta_description
      hash[:subscriptions_count] = @feed.subscriptions_count
    end
  end

  def description
    @feed.options.safe_dig("description")&.to_plain_text
  end

  def format_url(url)
    url = url.to_s.downcase
    url.split(Regexp.union(%w[/ _ - .])) - EXCLUDE
  end
end
