class FeedRefresher
  include BatchJobs
  include Sidekiq::Worker

  attr_accessor :force_refresh

  def perform(batch, priority_refresh)
    feed_ids = build_ids(batch)
    count = priority_refresh ? 1 : 0

    active_subscriptions = Subscription.select(:feed_id)
      .where(feed_id: feed_ids, active: true)
      .distinct
      .pluck(:feed_id)

    jobs = Feed.xml
      .where(id: active_subscriptions, active: true)
      .where("subscriptions_count > ?", count)
      .pluck(:id, :feed_url, :subscriptions_count)

    if jobs.present?
      Sidekiq::Client.push_bulk(
        "args" => jobs,
        "class" => "FeedDownloader",
        "queue" => "feed_downloader",
        "retry" => false
      )
    end
  end
end
