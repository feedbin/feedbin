module FeedCrawler
  class Parser
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: local_queue("parse"), retry: false

    def perform(feed_id, path, encoding = nil, crawl_data = {})
      @feed = Feed.find(feed_id)
      @feed.crawl_data = crawl_data

      parse_and_save(@feed, path, encoding: encoding)

      @feed.last_change_check = Time.now if check_for_changes?
      @feed.crawl_data.clear!
    rescue Feedkit::NotFeed => exception
      @feed.crawl_data.download_error(exception)
      Sidekiq.logger.info "Feedkit::NotFeed: feed_id=#{@feed.id} url=#{@feed.feed_url}"
    rescue => exception
      Sidekiq.logger.info "Exception: feed_id=#{@feed.id} url=#{@feed.feed_url} exception=#{exception.inspect}"
      ErrorService.notify(exception)
    ensure
      @feed.save!
    end

    def parse_and_save(feed, path, encoding: nil, web_sub: false, import: false)
      @feed ||= feed
      @import = import

      parsed = Feedkit::Parser.parse!(
        File.read(path, binmode: true),
        url: @feed.feed_url,
        encoding: encoding
      )

      filter    = EntryFilter.new(parsed.entries, check_for_changes: check_for_changes?, always_check_recent: true)
      entries   = filter.filter
      video_ids = entries.filter_map { _1.safe_dig(:data, :youtube_video_id) }

      parsed_feed = parsed.to_feed
      parsed_feed.delete(:title) if video_ids.present? && web_sub
      data = {
        "feed" => parsed_feed.merge({"id" => @feed.id}),
        "entries" => entries
      }

      if parsed.entries.find { _1.title.present? }
        data["feed"]["custom_icon_format"] = nil
      else
        data["feed"]["custom_icon_format"] = "round"
      end

      if video_ids.present?
        HarvestEmbeds.new.add_missing_to_queue(video_ids)
        job_id = YoutubeReceiver.perform_in(2.minutes, data)
        Sidekiq.logger.info "Enqueued YoutubeReceiver job_id=#{job_id} feed_id=#{@feed.id}"
      elsif import
        Receiver.new.perform(data)
      else
        job_id = Receiver.perform_async(data)
        Sidekiq.logger.info "Enqueued Receiver job_id=#{job_id} feed_id=#{@feed.id}"
      end

      Sidekiq.logger.info "Parser: stats=#{filter.stats} check_for_changes=#{check_for_changes?} url=#{@feed.feed_url} feed_id=#{@feed.id}"
      filter.stats.each do |stat, count|
        Honeybadger.increment_counter("feed.parser", count, source: stat)
      end

      post_id_count = parsed.entries.count { _1.entry.respond_to?(:post_id) && _1.entry.post_id.present? }
      Honeybadger.increment_counter("feed.post_id", post_id_count)
    ensure
      File.unlink(path) rescue Errno::ENOENT
    end

    private

    def check_for_changes?
      return @check_for_changes if defined?(@check_for_changes)
      if @import
        @check_for_changes = false
        return
      end

      last_check = @feed.last_change_check

      if last_check.nil?
        @check_for_changes = true
        return @check_for_changes
      end

      random_timeout = rand(12..24).hours.ago
      @check_for_changes = last_check.before?(random_timeout)
    end
  end
end
