class HarvestLinks
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :network_default

  def perform(entry_id)
    @entry = Entry.find(entry_id)

    urls = if @entry.tweet?
      find_tweet_urls
    elsif @entry.micropost?
      find_micropost_urls
    end

    if url = urls&.first
      page = MercuryParser.parse(url)
      @entry.data["saved_pages"] = {url => page.to_h}
      @entry.data["urls"] = urls
      @entry.save!
      if @entry.micropost? && @entry.urls.length == 1
        ImageCrawler::TwitterLinkImage.perform_async(@entry.public_id, nil, url)
      end
    end
    if @entry.tweet?
      @entry.content = ApplicationController.render template: "entries/_tweet_default", formats: :html, locals: {entry: @entry}, layout: nil
      @entry.save!
    end
  rescue HTTP::TimeoutError, HTTP::ConnectionError
  end

  def find_micropost_urls
    document = Nokogiri.HTML5(@entry.content)
    document.css("a").each_with_object([]) do |node, array|
      href = node["href"]
      text = node.text

      next unless extract_candidate?(href)

      if href == text
        array.push(href)
      elsif text !~ /^[@#]/
        array.push(href)
      end
    end
  end

  def find_tweet_urls
    tweets = [@entry.tweet.main_tweet]
    tweets.push(@entry.tweet.main_tweet.quoted_status) if @entry.tweet.main_tweet.quoted_status?

    tweets.each_with_object([]) do |tweet, array|
      tweet.urls.each do |url|
        url = url.expanded_url
        array.push(url.to_s) if extract_candidate?(url)
      end
    end
  end

  def extract_candidate?(url)
    parsed = Addressable::URI.heuristic_parse(url)
    return false if parsed.path.length < 2 && parsed.query.nil?
    return false if same_host?(parsed.host, "twitter.com")
    # entries.url is nullable and Entry#hostname rescues to nil besides. An
    # own-host we don't know cannot match anything, so nothing is excluded --
    # Regexp.escape(nil) took the whole job down instead.
    return false if @entry.hostname.present? && same_host?(parsed.host, @entry.hostname)
    true
  end

  # Both patterns used to be unanchored, with an unescaped dot, so example.com
  # matched notexample.com and example.com.evil.test alike.
  def same_host?(host, domain)
    host = host.to_s.downcase
    domain = domain.to_s.downcase
    host == domain || host.end_with?(".#{domain}")
  end

end
