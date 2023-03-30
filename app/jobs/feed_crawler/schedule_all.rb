require "sidekiq/api"
module FeedCrawler
  class ScheduleAll
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: :utility_critical

    COUNT_KEY = "feed_refresher_scheduler:count".freeze

    def perform
      queues = [Downloader, Parser, Receiver]
      if queues.all? {|queue| queue_empty?(queue.get_sidekiq_options["queue"]) }
        refresh_feeds
      end
    end

    def refresh_feeds
      feed = Feed.last
      if feed
        jobs = job_args(feed.id, 1, priority?)
        Sidekiq::Client.push_bulk(
          "args" => jobs,
          "class" => ScheduleBatch
        )
        increment
        report
      end
    end

    def priority?
      @priority ||= count % 2 == 0
    end

    def increment
      Librato.increment "refresh_feeds"
      Sidekiq.redis { |client| client.incr(COUNT_KEY) }
    end

    def report
      if ENV["FEED_REFRESHER_REPORT_URL"]
        HTTP.get(ENV["FEED_REFRESHER_REPORT_URL"])
      end
    end

    def count
      @count ||= begin
        result = Sidekiq.redis { |client| client.get(COUNT_KEY) } || 0
        result.to_i
      end
    end

    def queue_empty?(queue)
      queue = queue.to_s
      @queues ||= Sidekiq::Stats.new.queues
      @queues[queue].blank? || @queues[queue] == 0
    end
  end
end