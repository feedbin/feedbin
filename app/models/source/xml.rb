class Source::XML < Source
  def call
    if @config[:request].format == :xml
      url = @config[:request].last_effective_url
      @feed_options.push(FeedOption.new(url, url, url, "xml"))
      create_feeds!
    end
  end
end
