class Source::Youtube < Source
  URLS = [
    {
      template: "https://www.youtube.com/feeds/videos.xml?channel_id=%s".freeze,
      regex: Regexp.new(/https:\/\/www\.youtube\.com\/channel\/([^\/#\?]*)/),
    },
    {
      template: "https://www.youtube.com/feeds/videos.xml?user=%s".freeze,
      regex: Regexp.new(/https:\/\/www\.youtube\.com\/user\/([^\/#\?]*)/),
    },
    {
      template: "https://www.youtube.com/feeds/videos.xml?playlist_id=%s".freeze,
      regex: Regexp.new(/https:\/\/www\.youtube\.com\/playlist\?list=([^&]*)/),
    },
  ]

  def call
    if (match = URLS.find { |candidate| @config[:request].last_effective_url =~ candidate[:regex] }) && $1
      feed_url = match[:template] % $1
      option = FeedOption.new(feed_url, feed_url, nil, "youtube_options")
      @feed_options.push(option)
      create_feeds!
    elsif youtube_domain? && channel_id
      feed_url = "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
      option = FeedOption.new(feed_url, feed_url, nil, "youtube_options")
      @feed_options.push(option)
      create_feeds!
    end
  end

  def youtube_domain?
    @config[:request].last_effective_url.start_with?("https://www.youtube.com")
  end

  def channel_id
    @channel_id ||= begin
      id = document.css("meta[itemprop='channelId']")
      if id.present?
        id.first["content"]
      end
    end
  end
end
