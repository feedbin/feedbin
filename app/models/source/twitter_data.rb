class Source::TwitterData < Source

  def initialize(url, auth)
    @url = url
    @auth = auth
    @feeds = []
  end

  def find
    unless @auth.nil?
      recognized_url = Feedkit::TwitterURLRecognizer.new(@url, @auth.screen_name)
      if recognized_url.valid?
        twitter = Feedkit::Tweets.new(recognized_url, @auth.token, @auth.secret)
        feed = Feed.where(feed_url: recognized_url.url.to_s).take
        feed ||= Feed.create_from_parsed_feed(twitter.feed)
        feeds.push(feed)
      end
    end
  end
end
