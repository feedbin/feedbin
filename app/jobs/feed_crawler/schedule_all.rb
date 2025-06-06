module FeedCrawler
  class ScheduleAll
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: :utility_critical

    COUNT_KEY = "feed_refresher_scheduler:count".freeze
    LAST_REFRESH_KEY = "feed_refresher_scheduler:last_refresh".freeze

    def perform
      queues = [Downloader, Parser, Receiver]
      unless queues.all? { queue_empty?(it.get_sidekiq_options["queue"]) }
        Sidekiq.logger.info "skipping, crawl still processing"
        return
      end

      unless last_refresh.before?(15.minutes.ago)
        Sidekiq.logger.info "skipping, last crawl too recent"
        return
      end

      refresh_feeds
    end

    def refresh_feeds
      subscribed_feed_ids = Subscription.where(active: true).pluck("DISTINCT feed_id")
      standalone_feed_ids = Feed.where.not(standalone_request_at: nil).pluck(:id)
      feed_ids = (subscribed_feed_ids + standalone_feed_ids).uniq.shuffle

      feed_ids.each_slice(5_000) do |ids|
        jobs = Feed.xml.where(id: ids).filter_map do |feed|
          if feed.crawl_data.ok?(feed.feed_url)
            [feed.id, feed.feed_url, feed.subscriptions_count, feed.crawl_data.to_h]
          end
        end

        Sidekiq::Client.push_bulk("args" => jobs, "class" => Downloader) unless jobs.empty?
      end

      increment
      report
    end

    def priority?
      @priority ||= count % 2 == 0
    end

    def last_refresh
      last_refresh = Time.at(Sidekiq.redis { it.get(LAST_REFRESH_KEY) }.to_i)
    end

    def increment
      Librato.increment "refresh_feeds"
      Sidekiq.redis { _1.incr(COUNT_KEY) }
      Sidekiq.redis { _1.set(LAST_REFRESH_KEY, Time.now.to_i) }
    end

    def report
      if ENV["FEED_REFRESHER_REPORT_URL"]
        HTTP.get(ENV["FEED_REFRESHER_REPORT_URL"])
      end
    end

    def count
      @count ||= begin
        result = Sidekiq.redis { _1.get(COUNT_KEY) } || 0
        result.to_i
      end
    end
  end
end