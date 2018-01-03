class TwitterFeedRefresher
  include Sidekiq::Worker

  def perform
    Feed.where(feed_type: [:twitter, :twitter_home]).find_each do |feed|
      enqueue_feed(feed)
    end
  end

  def enqueue_feed(feed)
    user_ids = feed.subscriptions.where(active: true, muted: false).pluck(:user_id)
    if !user_ids.empty?
      users = User.where(id: user_ids)
      keys = users.map do |user|
        if user.twitter_access_token.present? && user.twitter_access_secret.present?
          {
            twitter_access_token: user.twitter_access_token,
            twitter_access_secret: user.twitter_access_secret
          }
        end
      end.compact

      if keys.present?
        Sidekiq::Client.push(
          'args'  => [feed.id, feed.feed_url, keys],
          'class' => 'TwitterFeedRefresher',
          'queue' => 'feed_refresher_fetcher',
          'retry' => false
        )
      end
    end
  end

end