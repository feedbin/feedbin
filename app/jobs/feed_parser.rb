class FeedParser
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: local_queue("feed_parser"), retry: false

  def perform(feed_id, feed_url, path, encoding = nil)
    @feed = Feed.find(feed_id)

    parsed = Feedkit::Parser.parse!(
      File.read(path, binmode: true),
      url: @feed.feed_url,
      encoding: encoding
    )

    filter = EntryFilter.new(parsed.entries, check_for_changes: check_for_changes?, always_check_recent: true)
    save(feed: parsed.to_feed, entries: filter.filter)
    clear_feed_errors!
    @feed.update(last_change_check: Time.now) if check_for_changes?

    Sidekiq.logger.info "FeedParser: stats=#{filter.stats} check_for_changes=#{check_for_changes?} url=#{@feed.feed_url} feed_id=#{@feed.id}"
    filter.stats.each do |stat, count|
      Librato.increment("feed.parser", source: stat, by: count)
    end
  rescue Feedkit::NotFeed => exception
    record_feed_error!(exception)
  ensure
    File.unlink(path) rescue Errno::ENOENT
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
    job_id = FeedRefresherReceiver.perform_async({
      "feed" => feed.merge({"id" => @feed.id}),
      "entries" => entries
    })
    Sidekiq.logger.info "Enqueued FeedRefresherReceiver job_id=#{job_id} feed_id=#{@feed.id}"
  end

  def clear_feed_errors!
    FeedCrawler::FeedStatusUpdate.new.perform(@feed.id)
  end

  def record_feed_error!(exception)
    exception = JSON.dump({date: Time.now.to_i, class: exception.class, message: exception.message, status: nil})
    FeedCrawler::FeedStatusUpdate.perform_async(@feed.id, exception)
    Sidekiq.logger.info "Feedkit::NotFeed: feed_id=#{@feed.id} url=#{@feed.feed_url}"
  end
end

class FeedParserCritical
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: local_queue("feed_parser_critical"), retry: false
  def perform(*args)
    FeedParser.new.perform(*args)
  end
end
