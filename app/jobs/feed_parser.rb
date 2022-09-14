class FeedParser
  include Sidekiq::Worker
  sidekiq_options queue: "feed_parser_#{Socket.gethostname}", retry: false

  def perform(feed_id, feed_url, path, encoding = nil)
    @feed_id = feed_id
    @feed_url = feed_url
    @path = path
    @encoding = encoding

    filter = EntryFilter.new(parsed_feed.entries)
    entries = filter.filter

    feed = parsed_feed.to_feed
    save(feed, entries) unless entries.empty?
    clear_feed_status!

    Sidekiq.logger.info "FeedParser feed=#{feed.inspect}"

    updates = filter.fingerprint_entries
    # update_fingerprints(updates)
  rescue Feedkit::NotFeed => exception
    Sidekiq.logger.info "Feedkit::NotFeed: id=#{@feed_id} url=#{@feed_url}"
    record_feed_error!(exception)
  ensure
    cleanup
  end

  def update_fingerprints(updates)
    return if updates.nil?

    public_ids = updates.keys

    cases = Entry.where(public_id: public_ids).select(:id, :fingerprint, :public_id).each_with_object([]) do  |entry, array|
      data = {
        id: entry.id,
        value: updates[entry.public_id]
      }
      array.push(Entry.sanitize_sql(["WHEN :id THEN :value::uuid", data]))
    end

    return if cases.empty?

    Sidekiq.logger.info "Updating fingerprints: id=#{@feed_id}"

    query = "fingerprint = CASE id %<cases>s END" % { cases: cases.join(" ")}

    Entry.where(public_id: public_ids).update_all(query)
  end

  private

  def parsed_feed
    @parsed_feed ||= begin
      body = File.read(@path, binmode: true)
      Feedkit::Parser.parse!(body, url: @feed_url, encoding: @encoding)
    end
  end

  def cleanup
    File.unlink(@path) rescue Errno::ENOENT
  end

  def save(feed, entries)
    FeedRefresherReceiver.perform_async({
      "feed" => feed.merge({"id" => @feed_id}),
      "entries" => entries
    })
  end

  def clear_feed_status!
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
  end
end

class FeedParserCritical
  include Sidekiq::Worker
  sidekiq_options queue: "feed_parser_critical_#{Socket.gethostname}", retry: false
  def perform(*args)
    FeedParser.new.perform(*args)
  end
end
