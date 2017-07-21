class RssAnchors

  def initialize(html, url, options = {})
    @html = html
    @url = url
    @limit = options[:limit]
  end

  def document
    @document ||= Nokogiri::HTML(@html)
  end

  def perform
    @perform ||= begin
      options = []
      options = document.search("a").each_with_object([]) do |link, array|
        if link_valid?(link)
          option = FeedOption.new(@url, link["href"])
          array.push(option)
        end
      end

      options = options.uniq { |option| option.title }
      options = options.uniq { |option| option.href }

      if options
        number = @limit || options.length
        options = options.first(number).each_with_object([]) do |option, array|
          if feed = rss_feed(option)
            array.push(feed)
          end
        end
      end
      options
    end
  end

  def host
    URI::parse(@url).host
  end

  def rss_feed(option)
    result = false
    if option.href.include?(host)
      response = HTTP.head(option.href)
      if response["Content-Type"] =~ /xml/
        request = FeedRequest.new(url: option.href)
        title = ParsedXMLFeed.new(request.body, request).title
        result = FeedOption.new(request.last_effective_url, request.last_effective_url, title, "rss_anchors")
      end
    end
    result
  end

  private

  def link_valid?(link)
    types = ["feed", "xml", "rss", "atom"]
    if href = link["href"]
      types.any? { |type| href.include?(type) }
    else
      false
    end
  end

end