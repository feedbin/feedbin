class ParsedFeedError < StandardError
  attr_reader :object

  def initialize(object)
    @object = object
  end
end

class ParsedFeed

  attr_reader :feed, :entries

  def initialize(feed_url:, url:, title:, last_modified:, etag:, hubs:, entries:)
    @feed = {
      feed_url: feed_url,
      url: url,
      title: title,
      last_modified: last_modified,
      etag: etag,
      hubs: hubs,
    }
    @entries = entries
  end

  def self.new_from_url(feed_url, options = {}, base_feed_url = nil)
    defaults = {user_agent: 'Feedbin', ssl_verify_peer: false, timeout: 20}
    options = defaults.merge(options)
    feed = Feedjira::Feed.fetch_and_parse(feed_url, options)
    if is_feed?(feed)
      normalize(feed, base_feed_url)
    else
      raise ParsedFeedError.new(feed), "Parse failed"
    end
  end

  private

  def self.normalize(feed, base_feed_url)
    new(
      feed_url: feed.feed_url.strip,
      url: get_site_url(feed),
      title: feed.title ? feed.title.strip : '(No title)',
      last_modified: feed.last_modified,
      etag: feed.etag ? feed.etag.strip.gsub(/^"/, '').gsub(/"$/, '') : nil,
      hubs: feed.hubs,
      entries: build_entries(feed, base_feed_url)
    )
  end

  def self.is_feed?(feed)
    feed.class.name.starts_with?('Feedjira')
  end

  def self.get_site_url(feed)
    if feed.url.present?
      url = feed.url
    else
      if feed.feed_url =~ /feedburner\.com/
        url = last_effective_url(feed.entries.first.url)
        url = url_from_host(url)
      else
        url = url_from_host(feed.feed_url)
      end
    end
    url
  end

  def self.url_from_host(link)
    uri = URI.parse(link)
    URI::HTTP.build(host: uri.host).to_s
  end

  def self.build_entries(feed, base_feed_url)
    entries = []
    if feed.entries.any?
      entries= feed.entries.map do |entry|
        ParsedEntry.new(entry: entry, feed: feed, base_feed_url: base_feed_url)
      end
      entries = entries.uniq { |entry| entry.public_id }
    end
    entries
  end

  def last_effective_url(url)
    result = Curl::Easy.http_head(url) do |curl|
      curl.follow_location = true
      curl.ssl_verify_peer = false
      curl.max_redirects = 5
      curl.timeout = 5
      curl.connect_timeout = 5
    end
    result.last_effective_url
  end

end
