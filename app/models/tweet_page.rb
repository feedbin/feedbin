class TweetPage
  def initialize(url, user)
    @url = url
    @user = user
  end

  def self.tweet(*args)
    instance = new(*args)
    data = instance.from_entry || instance.from_api
    {tweet: data} unless data.nil?
  end

  def from_entry
    return nil unless tweet?
    Entry.where(main_tweet_id: tweet_id).take&.main_tweet&.to_h
  end

  def from_api
    return nil unless tweet?
    @user.twitter_client&.status(tweet_id, tweet_mode: "extended")&.to_h
  rescue
    nil
  end

  def tweet?
    tweet_id.present?
  end

  def tweet_id
    matches = %r{https://(?:mobile\.)?twitter.com/[^/]*/status/(\d+)/?(?:$|\?|#)}.match(@url)
    matches&.captures&.first
  end
end