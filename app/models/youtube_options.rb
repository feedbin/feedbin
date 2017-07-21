class YoutubeOptions
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
    }
  ]

  def initialize(url)
    @url = url
  end

  def options
    options = []
    if (match = URLS.find { |candidate| @url =~ candidate[:regex] }) && $1
      feed_url = match[:template] % $1
      option = FeedOption.new(feed_url, feed_url, nil, "youtube_options")
      options.push(option)
    end
    options
  end

end
