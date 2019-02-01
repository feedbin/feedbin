class TweetsController < ApplicationController
  def thread
    @user = current_user
    @entry = Entry.find(params[:id])
    @tweets = Rails.cache.fetch("thread:#{@entry.id}", expires_in: 2.minutes) {
      parents = load_parents
      replies = load_replies(parents)
      tweets = load_author_replies(replies, parents)

      unless tweets.find { |tweet| tweet.id == @entry.main_tweet.id }
        tweets = tweets.unshift(@entry.main_tweet)
      end
      tweets = parents.concat(tweets)
      tweets.uniq { |tweet| tweet.id }
    }
    @parent = @tweets.first
  end

  private

  def authorize
    super && current_user.can_read_entry?(params[:id])
  end

  def client
    @client ||= ::Twitter::REST::Client.new { |config|
      config.consumer_key = ENV["TWITTER_KEY"]
      config.consumer_secret = ENV["TWITTER_SECRET"]
      config.access_token = @user.twitter_access_token
      config.access_token_secret = @user.twitter_access_secret
    }
  end

  def load_parents
    parents = []
    while parent = load_parent(parent)
      parents.unshift(parent)
    end
    parents
  end

  def load_replies(parents)
    parent = parents.first || @entry.main_tweet
    query = "to:#{parent.user.screen_name} AND filter:replies"
    options = {
      since_id: parent.id,
      result_type: "recent",
      include_entities: true,
      tweet_mode: "extended",
      count: 100,
    }
    results = client.search(query, options)
    tweets = results.take(100).select { |tweet|
      tweet.in_reply_to_status_id? &&
        tweet.in_reply_to_status_id == parent.id &&
        tweet.user.id != parent.user.id &&
        !parents.find { |t| tweet.id == t.id }
    }.reverse
    OpenStruct.new(tweets: tweets, search_metadata: results.to_h[:search_metadata])
  end

  def load_author_replies(replies, parents)
    parent = parents.first || @entry.main_tweet
    options = {
      include_rts: false,
      max_id: replies.search_metadata[:max_id],
      since_id: parent.id,
      tweet_mode: "extended",
      count: 200,
      exclude_replies: false,
    }
    author_replies = client.user_timeline(parent.user.id, options)

    parent_id = parent.id
    thread = author_replies.each_with_object([]) { |tweet, array|
      reply = author_replies.find { |author_reply|
        author_reply.in_reply_to_status_id == parent_id
      }
      if reply
        parent_id = reply.id
        array.push(reply)
      end
    }

    tweets = replies.tweets.each_with_object([]) { |tweet, array|
      array.push(tweet)
      if reply = author_replies.find { |author_reply| author_reply.in_reply_to_status_id == tweet.id }
        array.push(reply)
      end
    }

    tweets.unshift(*thread)
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
  rescue Twitter::Error::Forbidden
    false
  end
end
