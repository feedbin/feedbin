class FeedFetcher

  attr_accessor :feed, :feed_options

  def initialize(url, site_url = nil)
    @url          = normalize_url(url)
    @site_url     = normalize_url(site_url) if site_url
    @feed         = nil
    @raw_feed     = nil
    @parsed_feed  = nil
    @feed_options = []
  end

  def create_feed!
    unless feed_exists?
      create_or_get_options
    end
    self
  end

  def feed_exists?
    @feed = Feed.where(feed_url: @url).first
    @feed.instance_of?(Feed)
  end

  def normalize_url(url)
    url = url.strip
    url = url.gsub(/^ht*p(s?):?\/*/, 'http\1://')
    url = url.gsub(/^feed:\/\//, 'http://')
    if url =~ /^https?:\/\//
      return url
    else
      "http://#{url}"
    end
  end

  def create_or_get_options
    @parsed_feed = fetch_and_parse
    if is_feed?(@parsed_feed)
      create!
    else
      get_options
    end
  end

  def get_options
    content = Feedjira::Feed.fetch_raw(@url, {user_agent: 'Feedbin', ssl_verify_peer: false})
    if content.is_a?(String)
      content = Nokogiri::HTML(content)

      # Case insensitive rss link search
      links = content.search("//link[translate(@type, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = 'application/rss+xml'] |" +
                             "//link[translate(@type, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = 'application/atom+xml']")

      links.map do |link|
        href = link.get_attribute('href')
        title = link.get_attribute('title')
        unless href.nil?
          href = href.gsub(/^feed:\/\//, 'http://')
          href = URI.join(@url, href).to_s unless href.start_with?('http')
          if title.nil?
            title = href
          end
          @feed_options << { href: href, title: link['title'], site_url: @url }
        end
      end
    end

    if @feed_options.length == 1
      @site_url = @url
      @url = @feed_options.first[:href]

      @parsed_feed = fetch_and_parse
      if is_feed?(@parsed_feed)
        create!
      else
        get_options
      end
    end

  end

  def create!
    # Figure out what the url to the site is
    unless @site_url
      get_site_url
    end

    # now that we have a feed url recheck if a feed exists
    @feed = Feed.where(feed_url: @parsed_feed.feed_url).first

    unless @feed
      @feed = Feed.create_from_feedjira(@parsed_feed, @site_url)
      if @parsed_feed.respond_to?(:hubs) && !@parsed_feed.hubs.blank?
        hub_secret = Push::hub_secret(@feed.id)
        push_subscribe(@parsed_feed, @feed.id, Push::callback_url(@feed), hub_secret)
      end
    end

  end

  def push_subscribe(feedjira, feed_id, push_callback, hub_secret)
    begin
      feedjira.hubs.each do |hub|
        uri = URI(hub)
        uri.scheme = 'https' # force https encrypt request
        Curl.post(uri.to_s, {
          'hub.mode' => 'subscribe',
          'hub.topic' => feedjira.feed_url,
          'hub.secret' => hub_secret,
          'hub.callback' => push_callback,
          'hub.verify' => 'async'
        })
      end
    rescue Exception => e
      if defined?(Honeybadger)
        Honeybadger.notify(
          error_class: "PuSH",
          error_message: "PuSH Subscribe Failed",
          parameters: {exception: e}
        )
      end
    end
  end

  def get_site_url
    if @site_url
      @site_url = @site_url
    elsif @parsed_feed.url
      @site_url = @parsed_feed.url
    elsif @url =~ /feedburner\.com/
      begin
        @site_url = url_from_link(LongURL.expand(@parsed_feed.entries.first.url))
      rescue Exception
        @site_url = url_from_link(@url)
      end
    else
      @site_url = url_from_link(@url)
    end
  end

  def url_from_link(link)
    uri = URI.parse(link)
    URI::HTTP.build(host: uri.host).to_s
  end

  def is_feed?(feed)
    feed.class.name.starts_with?('Feedjira')
  end

  # Fetch and normalize feed
  def fetch_and_parse(options = {}, saved_feed_url = nil)
    defaults = {user_agent: 'Feedbin', ssl_verify_peer: false}
    options = defaults.merge(options)
    feedjira = nil
    Timeout::timeout(20) do
      feedjira = Feedjira::Feed.fetch_and_parse(@url, options)
    end
    if feedjira.respond_to?(:hubs) && !feedjira.hubs.blank? && options[:push_callback] && options[:feed_id]
      if @url == feedjira.feed_url
        push_subscribe(feedjira, options[:feed_id], options[:push_callback], options[:hub_secret])
      end
    end
    normalize(feedjira, options, saved_feed_url)
  end

  def parse(xml_string, saved_feed_url)
    feedjira = Feedjira::Feed.parse(xml_string)
    normalize(feedjira, {}, saved_feed_url)
  end

  def normalize(feedjira, options = {}, saved_feed_url = nil)
    if feedjira && feedjira.respond_to?(:feed_url)
      feedjira.etag          = feedjira.etag ? feedjira.etag.strip.gsub(/^"/, '').gsub(/"$/, '') : nil
      feedjira.last_modified = feedjira.last_modified
      feedjira.title         = feedjira.title ? feedjira.title.strip : '(No title)'
      feedjira.feed_url      = feedjira.feed_url.strip
      feedjira.url           = feedjira.url ? feedjira.url.strip : nil
      feedjira.entries.map do |entry|
        if entry.try(:content)
          content = entry.content
        elsif entry.try(:summary)
          content = entry.summary
        elsif entry.try(:description)
          content = entry.description
        else
          content = nil
        end

        if entry.try(:author)
          entry.author = entry.author
        elsif entry.try(:itunes_author)
          entry.author = entry.itunes_author
        else
          entry.author = nil
        end

        entry.content         = content ? content.strip : nil
        entry.title           = entry.title ? entry.title.strip : nil
        entry.url             = entry.url ? entry.url.strip : nil
        entry.entry_id        = entry.entry_id ? entry.entry_id.strip : nil
        entry._public_id_     = build_public_id(entry, feedjira, saved_feed_url)
        entry._old_public_id_ = build_public_id(entry, feedjira)
        if entry.try(:enclosure_type) && entry.try(:enclosure_url)
          data = {}
          data[:enclosure_type] = entry.enclosure_type ? entry.enclosure_type : nil
          data[:enclosure_url] = entry.enclosure_url ? entry.enclosure_url : nil
          data[:enclosure_length] = entry.enclosure_length ? entry.enclosure_length : nil
          data[:itunes_duration] = entry.itunes_duration ? entry.itunes_duration : nil
          entry._data_ = data
        end
      end
      if feedjira.entries.any?
        feedjira.entries = feedjira.entries.uniq { |entry| entry._public_id_ }
      end
    end
    feedjira
  end

  def log(message)
    Rails.logger.info(message)
  end

  # This is the id strategy
  # All values are stripped
  # feed url + id
  # feed url + link + utc iso 8601 date
  # feed url + link + title

  # WARNING: changes to this will break how entries are identified
  # This can only be changed with backwards compatibility in mind
  def build_public_id(entry, feedjira, saved_feed_url = nil)
    if saved_feed_url
      id_string = saved_feed_url.dup
    else
      id_string = feedjira.feed_url.dup
    end

    if entry.entry_id
      id_string << entry.entry_id.dup
    else
      if entry.url
        id_string << entry.url.dup
      end
      if entry.published
        id_string << entry.published.iso8601
      end
      if entry.title
        id_string << entry.title.dup
      end
    end
    Digest::SHA1.hexdigest(id_string)
  end


end
