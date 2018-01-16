class TweetsController < ApplicationController

  def thread
    @user = current_user
    @entry = Entry.find(params[:id])
    @tweets = Rails.cache.fetch("thread:#{@entry.id}") do
      replies = load_replies
      tweets = load_author_replies(replies)
      tweets = tweets.unshift(@entry.main_tweet)
      parents = load_parents
      parents.concat(tweets)
    end
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

  def load_parents
    parents = []
    while parent = load_parent(parent)
      parents.unshift(parent)
    end
    parents
  end

  def load_parent(parent)
    if parent.nil?
      parent = @entry.main_tweet
    end
    if parent.in_reply_to_status_id?
      client.status(parent.in_reply_to_status_id, tweet_mode: "extended")
    else
      false
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
    results = client.search(query, options)
    tweets = results.take(100).select do |tweet|
      tweet.in_reply_to_status_id? && tweet.in_reply_to_status_id == @entry.main_tweet.id
    end.reverse
    OpenStruct.new(tweets: tweets, search_metadata: results.to_h[:search_metadata])
  end

  def load_author_replies(replies)
    options = {
      include_rts:	false,
      max_id:	replies.search_metadata[:max_id],
      since_id:	@entry.main_tweet.id,
      tweet_mode:	"extended",
      count: 100,
    }
    author_replies = client.user_timeline(@entry.main_tweet.user.id, options)
    replies.tweets.each_with_object([]) do |tweet, array|
      array.push(tweet)
      if reply = author_replies.find {|author_reply| author_reply.in_reply_to_status_id == tweet.id }
        array.push(reply)
      end
    end
  end

end
