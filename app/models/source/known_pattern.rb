class Source::KnownPattern < Source
  URLS = [
    {
      template: "https://www.youtube.com/feeds/videos.xml?channel_id=%s".freeze,
      regex: Regexp.new(/https:\/\/www\.youtube\.com\/channel\/([^\/#\?]*)/)
    },
    {
      template: "https://www.youtube.com/feeds/videos.xml?user=%s".freeze,
      regex: Regexp.new(/https:\/\/www\.youtube\.com\/user\/([^\/#\?]*)/)
    },
    {
      template: "https://www.youtube.com/feeds/videos.xml?playlist_id=%s".freeze,
      regex: Regexp.new(/https:\/\/www\.youtube\.com\/playlist\?list=([^&]*)/)
    },
    {
      template: "https://www.reddit.com/r/%s.rss".freeze,
      regex: Regexp.new(/https:\/\/www\.reddit\.com\/r\/([^\/#\?]*)/)
    },
    {
      template: "https://vimeo.com/%s/videos/rss".freeze,
      regex: Regexp.new(/https:\/\/vimeo\.com\/([^\/#\?]*)/)
    }
  ]

  def find
    if (match = URLS.find { |candidate| response.url =~ candidate[:regex] }) && $1
      feed_url = match[:template] % $1
      feed = create_from_url!(feed_url)
      feeds.push(feed) if feed
    elsif document? && youtube_domain? && channel_id
      feed_url = "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
      feed = create_from_url!(feed_url)
      feeds.push(feed) if feed
    end
  end

  def youtube_domain?
    response.url.start_with?("https://www.youtube.com")
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
