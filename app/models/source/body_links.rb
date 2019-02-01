class Source::BodyLinks < Source
  def call
    if @config[:request].format == :html
      find_links
    end
  end

  def find_links
    options = document.search("a").each_with_object([]) { |link, array|
      if link_valid?(link)
        option = FeedOption.new(@config[:request].last_effective_url, link["href"])
        array.push(option)
      end
    }

    options = options.uniq { |option| option.title }
    options = options.uniq { |option| option.href }

    if options
      limit = 5
      @feed_options = options.first(limit).each_with_object([]) { |option, array|
        if feed = rss_feed(option)
          array.push(feed)
        end
      }
      create_feeds!
    end
  end

  private

  def host
    URI.parse(@config[:request].last_effective_url).host
  end

  def rss_feed(option)
    result = false
    if option.href.include?(host)
      response = HTTP.head(option.href)
      if /xml/.match?(response["Content-Type"])
        request = Feedkit::Request.new(url: option.href)
        title = Feedkit::Feedkit.new.fetch_and_parse(option.href, request: request).title
        result = FeedOption.new(request.last_effective_url, request.last_effective_url, title, "rss_anchors")
      end
    end
    result
  end

  def link_valid?(link)
    types = ["feed", "xml", "rss", "atom"]
    if href = link["href"]
      types.any? { |type| href.include?(type) }
    else
      false
    end
  end

  def document
    @document ||= Nokogiri::HTML(@config[:request].body)
  end
end
