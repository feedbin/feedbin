class FeedRefresher
  include BatchJobs
  include Sidekiq::Worker

  attr_accessor :force_refresh

  def perform(batch, priority_refresh)
    feed_ids = build_ids(batch)
    count = priority_refresh ? 1 : 0

    active = Subscription.select(:feed_id)
      .where(feed_id: feed_ids, active: true)
      .distinct
      .pluck(:feed_id)

    subscriptions = Feed.xml
      .where(id: active, active: true)
      .where("subscriptions_count > ?", count)
      .pluck(:id, :feed_url, :subscriptions_count)

    standalone = Feed.where(
      standalone_request_at: 1.month.ago..,
      id: feed_ids - active
    ).pluck(:id, :feed_url).map {|args| args.push(1)}

    jobs = subscriptions + standalone

    if jobs.present?
      Sidekiq::Client.push_bulk(
        "args"      => jobs.shuffle,
        "class"     => "Crawler::Refresher::FeedDownloader",
        "queue"     => "feed_downloader",
        "retry"     => false,
        "dead"      => false,
        "backtrace" => false
      )
    end
  end
end
