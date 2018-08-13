class Source::Guess < Source
  def call
    if @config[:request].format == :html
      host = URI.parse(@config[:request].last_effective_url).host
      if @config[:request].body =~ /tumblr\.com/i
        url = URI::HTTP.build(host: host, path: "/rss").to_s
        @feed_options.push(FeedOption.new(url, url, url, "guess"))
      elsif @config[:request].body =~ /wordpress/i
        url = URI::HTTP.build(host: host, path: "/feed").to_s
        @feed_options.push(FeedOption.new(url, url, url, "guess"))
      end
      create_feeds!
    end
  end
end
