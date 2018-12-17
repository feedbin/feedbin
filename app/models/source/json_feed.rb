class Source::JSONFeed < Source
  def call
    if @config[:request].format == :json_feed
      url = @config[:request].last_effective_url
      @feed_options.push(FeedOption.new(url, url, url, "json_feed"))
      create_feeds!
    end
  end
end
