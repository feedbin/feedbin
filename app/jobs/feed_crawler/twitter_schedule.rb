module FeedCrawler
  class TwitterSchedule
    include Sidekiq::Worker
    sidekiq_options queue: :worker_slow_critical

    def perform
      Feed.where(feed_type: [:twitter, :twitter_home]).find_each do |feed|
        enqueue_feed(feed)
      end
    end

    def enqueue_feed(feed, user = nil)
      keys = load_keys(feed, user)

      if keys.present?
        job_class = user ? TwitterDownloaderCritical : TwitterDownloader
        job_class.perform_async(feed.id, feed.feed_url, keys)
      end
    end

    def load_keys(feed, user = nil)
      user_ids = if user
        [user.id]
      else
        feed.subscriptions.where(active: true).pluck(:user_id)
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
            twitter_access_secret: user.twitter_access_secret
          }
        end
      }.compact
    end
  end
end