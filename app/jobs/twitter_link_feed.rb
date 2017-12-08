class TwitterLinkFeed
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, activate)
    if activate
      user = User.find(user_id)
      client = TwitterAPI.new(user.twitter_access_token, user.twitter_access_secret)
      url = "https://twitter.com/#{user.twitter_screen_name}/home_timeline"
      default_options = {
        count: 100,
        tweet_mode: "extended"
      }
      tweets = client.client.home_timeline(default_options)
      feed = ParsedTwitterFeed.new(url, tweets, :home_timeline, user.twitter_screen_name)
      feed = Feed.create_from_parsed_feed(feed)
      user.subscriptions.create!(feed: feed)
    else
      # turn off feed
    end
  end

end
