class Source::Reddit < Source
  URLS = [
    {
      template: "https://www.reddit.com/r/%s.rss".freeze,
      regex: Regexp.new(/https:\/\/www\.reddit\.com\/r\/([^\/#\?]*)/),
    }
  ]

  def call
    if (match = URLS.find { |candidate| @config[:request].last_effective_url =~ candidate[:regex] }) && $1
      feed_url = match[:template] % $1
      option = FeedOption.new(feed_url, feed_url, nil, "reddit_options")
      @feed_options.push(option)
      create_feeds!
    end
  end
end
