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

    filter = EntryFilter.new(parsed.entries)
    save(feed: parsed.to_feed, entries: filter.filter)
    Sidekiq.logger.info "FeedParser: stats=#{filter.stats} url=#{@feed.feed_url} feed_id=#{@feed.id}"
    filter.stats.each do |stat, count|
      Librato.increment("feed.parser", source: stat, by: count)
    end
  rescue Feedkit::NotFeed => exception
    record_feed_error!(exception)
  ensure
    File.unlink(path) rescue Errno::ENOENT
  end

  private

  def save(feed:, entries:)
    job_id = FeedRefresherReceiver.perform_async({
      "feed" => feed.merge({"id" => @feed.id}),
      "entries" => entries
    })
    Sidekiq.logger.info "Enqueued FeedRefresherReceiver job_id=#{job_id} feed_id=#{@feed.id}"
    clear_feed_errors!
  end

  def clear_feed_errors!
    Sidekiq::Client.push(
      "args" => [@feed.id],
      "class" => "Crawler::Refresher::FeedStatusUpdate",
      "queue" => "feed_downloader_critical"
    )
  end

  def record_feed_error!(exception)
    exception = JSON.dump({date: Time.now.to_i, class: exception.class, message: exception.message, status: nil})
    Sidekiq::Client.push(
      "args" => [@feed.id, exception],
      "class" => "Crawler::Refresher::FeedStatusUpdate",
      "queue" => "feed_downloader_critical"
    )
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
