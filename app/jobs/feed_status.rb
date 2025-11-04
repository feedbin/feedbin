class FeedStatus
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  def perform(feed_id = nil, schedule = false)
    if schedule
      build
    else
      update(feed_id)
    end
  end

  def update(feed_id)
    feed = Feed.find(feed_id)
    cache = FeedbinUtils.shared_cache(feed.redirect_key)
    feed.update(redirected_to: cache[:to], current_feed_url: cache[:to])
  end

  def build
    enqueue_all(Feed, self.class)
  end
end
