class TwitterFeedRefresher
  include Sidekiq::Worker

  def perform
    Feed.where(feed_type: [:twitter, :twitter_home]).find_each do |feed|
      enqueue_feed(feed)
    end
  end

  def enqueue_feed(feed, user = nil)
    keys = load_keys(feed, user)

    if keys.present?
      args = {
        "args" => [feed.id, feed.feed_url, keys],
        "class" => "TwitterFeedRefresherCritical",
        "queue" => "feed_refresher_fetcher_critical",
        "retry" => false,
        "at" => Time.now.to_i + rand(0..6.minutes.to_i),
      }

      if user
        args.delete("at")
      end

      Sidekiq::Client.push(args)
    end
  end

  def load_keys(feed, user = nil)
    user_ids = if user
      [user.id]
    else
      feed.subscriptions.where(active: true, muted: false).pluck(:user_id)
    end

    users = User.where(id: user_ids)
    users.map { |user|
      user_matches = true
      if feed.twitter_home?
        url = Feedkit::TwitterURLRecognizer.new(feed.feed_url, nil)
        user_matches = (user.twitter_screen_name == url.screen_name)
      end
      if user.twitter_access_token.present? && user.twitter_access_secret.present? && user_matches
        {
          twitter_access_token: user.twitter_access_token,
          twitter_access_secret: user.twitter_access_secret,
        }
      end
    }.compact
  end
end
