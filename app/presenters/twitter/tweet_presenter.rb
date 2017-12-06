class Twitter::TweetPresenter < BasePresenter

  presents :tweet

  def text
    if tweet_hash[:entities]
      Twitter::Autolink.auto_link_with_json(tweet_hash[:full_text], tweet_hash[:entities]).html_safe
    else
      tweet_hash[:full_text]
    end
  end

  def main_tweet
    (tweet.retweeted_status?) ? tweet.retweeted_status : tweet
  end

  def tweet_hash
    @tweet_hash ||= main_tweet.to_h
  end

  def name
    main_tweet.user.name
  end

  def screen_name
    "@" + main_tweet.user.screen_name
  end

  def media
    main_tweet.media
  end

  def urls
    main_tweet.urls
  end

  def retweeted_message
    (tweet.user.name || "@" + tweet.user.screen_name) + " Retweeted"
  end

  def profile_image_uri
    if main_tweet.user.profile_image_uri?
      main_tweet.user.profile_image_uri("bigger")
    else
      # default twitter avatar
    end
  end

end