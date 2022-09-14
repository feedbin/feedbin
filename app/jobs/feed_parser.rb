class FeedParser
  include Sidekiq::Worker
  sidekiq_options queue: "feed_parser_#{Socket.gethostname}", retry: false

  def perform(feed_id, feed_url, path, encoding = nil)
    @feed_id = feed_id
    @feed_url = feed_url

    parsed = Feedkit::Parser.parse!(
      File.read(path, binmode: true),
      url: @feed_url,
      encoding: encoding
    )

    filter = EntryFilter.new(parsed.entries)
    save(feed: parsed.to_feed, entries: filter.filter)
    Sidekiq.logger.info "FeedParser: stats=#{filter.stats} url=#{@feed_url} id=#{@feed_id}"
  rescue Feedkit::NotFeed => exception
    record_feed_error!(exception)
  ensure
    File.unlink(path) rescue Errno::ENOENT
  end

  private

  def save(feed:, entries:)
    FeedRefresherReceiver.perform_async({
      "feed" => feed.merge({"id" => @feed_id}),
      "entries" => entries
    })
    clear_feed_errors!
  end

  def clear_feed_errors!
    Sidekiq::Client.push(
      "args" => [@feed_id],
      "class" => "Crawler::Refresher::FeedStatusUpdate",
      "queue" => "feed_downloader_critical"
    )
  end

  def record_feed_error!(exception)
    exception = JSON.dump({date: Time.now.to_i, class: exception.class, message: exception.message, status: nil})
    Sidekiq::Client.push(
      "args" => [@feed_id, exception],
      "class" => "Crawler::Refresher::FeedStatusUpdate",
      "queue" => "feed_downloader_critical"
    )
    Sidekiq.logger.info "Feedkit::NotFeed: id=#{@feed_id} url=#{@feed_url}"
  end
end

class FeedParserCritical
  include Sidekiq::Worker
  sidekiq_options queue: "feed_parser_critical_#{Socket.gethostname}", retry: false
  def perform(*args)
    FeedParser.new.perform(*args)
  end
end
