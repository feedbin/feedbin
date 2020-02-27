class Source::Guess < Source
  def call
    if @config[:request].format == :html
      host = URI.parse(@config[:request].last_effective_url).host

      rss = URI::HTTP.build(host: host, path: "/rss").to_s
      @feed_options.push(FeedOption.new(rss, rss, rss, "guess"))

      feed = URI::HTTP.build(host: host, path: "/feed").to_s
      @feed_options.push(FeedOption.new(feed, feed, feed, "guess"))

      create_feeds!
    end
  end
end
