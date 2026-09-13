module FeedCrawler
  class Schedule
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: :utility_critical

    COUNT_KEY = "feed_refresher_scheduler:count".freeze
    LAST_REFRESH_KEY = "feed_refresher_scheduler:last_refresh".freeze
    LOCK_KEY = "feed_refresher_scheduler:lock".freeze
    LOCK_TTL = 15.minutes

    def perform
      queues = [Downloader, Receiver]
      unless queues.all? { queue_empty?(it.get_sidekiq_options["queue"]) }
        Sidekiq.logger.info "skipping, crawl still processing"
        return
      end

      unless last_refresh.before?(15.minutes.ago)
        Sidekiq.logger.info "skipping, last crawl too recent: #{last_refresh}"
        return
      end

      # The guards above only read. Jobs that queue up during a deploy start
      # together once the workers return, and each one passes both guards
      # until the first push lands. The lock is one atomic check-and-set, so
      # exactly one of them refreshes; the rest skip. It marks a refresh in
      # progress, so it is released at the end; the last-refresh guard owns
      # the cool-down, and the TTL only bounds a run that dies mid-way.
      unless RedisLock.acquire(LOCK_KEY, LOCK_TTL.to_i)
        Sidekiq.logger.info "skipping, another crawl schedule holds the lock"
        return
      end

      begin
        refresh_feeds
      ensure
        Sidekiq.redis { _1.del(LOCK_KEY) }
      end
    end

    def refresh_feeds
      subscribed_feed_ids = Subscription.where(active: true).pluck("DISTINCT feed_id")
      # A feed not requested within the TTL has no live reader and leaves the
      # crawl set; the podcast controller's touch re-adds it on its next
      # request.
      standalone_feed_ids = Feed
        .where("standalone_request_at > ?", StandaloneRetention::TTL.ago)
        .pluck(:id)
      # Required, not defensive: this method consults only `Subscription`, so
      # an Airshow feed reaches the crawler solely through the standalone
      # flag. Without this term, a listener silent for 90 days would stop
      # getting new episodes.
      podcast_feed_ids = PodcastSubscription.distinct.pluck(:feed_id)
      feed_ids = (subscribed_feed_ids + standalone_feed_ids + podcast_feed_ids).uniq.shuffle

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