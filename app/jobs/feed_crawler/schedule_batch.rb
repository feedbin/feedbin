module FeedCrawler
  class ScheduleBatch
    include SidekiqHelper
    include Sidekiq::Worker

    sidekiq_options queue: :utility_critical

    attr_accessor :force_refresh

    def perform(batch, priority_refresh)
      feed_ids = build_ids(batch).shuffle
      count = priority_refresh ? 1 : 0

      active = Subscription.select(:feed_id)
        .where(feed_id: feed_ids, active: true)
        .distinct
        .pluck(:feed_id)

      subscriptions = Feed.xml
        .where(id: active, active: true)
        .where("subscriptions_count > ?", count)

      standalone = Feed
        .where(id: feed_ids - active)
        .where.not(standalone_request_at: nil)

      jobs = (subscriptions + standalone).filter_map do |feed|
        if feed.crawl_data.ok?(feed.feed_url)
          [feed.id, feed.feed_url, feed.subscriptions_count, feed.crawl_data.to_h]
        end
      end

      if jobs.present?
        Sidekiq::Client.push_bulk(
          "args"  => jobs.shuffle,
          "class" => Downloader
        )
      end
    end
  end
end