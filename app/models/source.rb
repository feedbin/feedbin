class Source
  attr_reader :options

  def initialize(url, config)
    @url = url
    @config = config
    @feed_options = []
  end

  def create_feeds!
    @feed_options.each_with_object([]) { |feed_option, array|
      array.push(create_feed(feed_option))
    }.compact.uniq
  end

  def create_feed(option)
    Librato.increment("feed_finder.#{option.source}")
    feed = Feed.where(feed_url: option.href).take

    unless feed
      request = @config[:request]
      if request.nil? || request.last_effective_url != option.href
        request = Feedkit::Request.new(url: option.href)
      end

      feed = Feed.where(feed_url: request.last_effective_url).take

      if !feed && [:xml, :json_feed].include?(request.format)
        parsed_feed = Feedkit::Feedkit.new.fetch_and_parse(request.last_effective_url, request: request)
        feed = Feed.create_from_parsed_feed(parsed_feed)
      end
    end
    feed
  end
end
