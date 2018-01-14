class TweetsController < ApplicationController

  def thread
    @user = current_user
    @entry = Entry.find(params[:id])
    @tweets = load_replies
  end

  private

  def authorize
    super && current_user.can_read_entry?(params[:id])
  end

  def client
    @client ||= ::Twitter::REST::Client.new do |config|
      config.consumer_key        = ENV['TWITTER_KEY']
      config.consumer_secret     = ENV['TWITTER_SECRET']
      config.access_token        = @user.twitter_access_token
      config.access_token_secret = @user.twitter_access_secret
    end
  end

  def load_replies
    query = "to:#{@entry.main_tweet.user.screen_name} AND filter:replies"
    options = {
      since_id: @entry.main_tweet.id,
      result_type: "recent",
      include_entities: true,
      tweet_mode: "extended",
      count: 100,
    }
    logger.info { "----------------------" }
    logger.info { query.inspect }
    logger.info { options.inspect }
    logger.info { "----------------------" }
    tweets = client.search(query, options).take(100)
    tweets.select do |tweet|
      tweet.in_reply_to_status_id? && tweet.in_reply_to_status_id == @entry.main_tweet.id
    end
  end

end
