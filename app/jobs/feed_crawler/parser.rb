module FeedCrawler
  class Parser
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: local_queue("parse"), retry: false

    def perform(feed_id, path, encoding = nil, crawl_data = {})
      @feed = Feed.find(feed_id)
      @feed.crawl_data = crawl_data

      parsed = Feedkit::Parser.parse!(
        File.read(path, binmode: true),
        url: @feed.feed_url,
        encoding: encoding
      )

      filter = EntryFilter.new(parsed.entries, check_for_changes: check_for_changes?, always_check_recent: true)
      save(feed: parsed.to_feed, entries: filter.filter)

      @feed.last_change_check = Time.now if check_for_changes?
      @feed.crawl_data.clear!

      Sidekiq.logger.info "Parser: stats=#{filter.stats} check_for_changes=#{check_for_changes?} url=#{@feed.feed_url} feed_id=#{@feed.id}"
      filter.stats.each do |stat, count|
        Librato.increment("feed.parser", source: stat, by: count)
      end
    rescue Feedkit::NotFeed => exception
      @feed.crawl_data.download_error(exception)
      Sidekiq.logger.info "Feedkit::NotFeed: feed_id=#{@feed.id} url=#{@feed.feed_url}"
    ensure
      File.unlink(path) rescue Errno::ENOENT
      @feed.save!
    end

    private

    def check_for_changes?
      return @check_for_changes if defined?(@check_for_changes)
      last_check = @feed.last_change_check

      if last_check.nil?
        @check_for_changes = true
        return @check_for_changes
      end

      random_timeout = rand(12..24).hours.ago
      @check_for_changes = last_check.before?(random_timeout)
    end

    def save(feed:, entries:)
      job_id = Receiver.perform_async({
        "feed" => feed.merge({"id" => @feed.id}),
        "entries" => entries
      })
      Sidekiq.logger.info "Enqueued Receiver job_id=#{job_id} feed_id=#{@feed.id}"
    end
  end
end
