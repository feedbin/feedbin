# frozen_string_literal: true

module Crawler
  module Refresher
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

        save(parsed_feed.to_feed, entries) unless entries.empty?
        FeedStatus.clear!(@feed_id)
        filter.fingerprint_entries
      rescue Feedkit::NotFeed => exception
        Sidekiq.logger.info "Feedkit::NotFeed: id=#{@feed_id} url=#{@feed_url}"
        FeedStatus.new(@feed_id).error!(exception)
      ensure
        cleanup
      end

      def save(feed, entries)
        Sidekiq::Client.push(
          "class" => "FeedRefresherReceiver",
          "queue" => "feed_refresher_receiver",
          "args" => [{
            "feed" => feed.merge({"id" => @feed_id}),
            "entries" => entries
          }]
        )
      end

      def parsed_feed
        @parsed_feed ||= begin
          body = File.read(@path, binmode: true)
          Feedkit::Parser.parse!(body, url: @feed_url, encoding: @encoding)
        end
      end

      def cleanup
        File.unlink(@path) rescue Errno::ENOENT
      end
    end

    class FeedParserCritical
      include Sidekiq::Worker
      sidekiq_options queue: "feed_parser_critical_#{Socket.gethostname}", retry: false
      def perform(*args)
        FeedParser.new.perform(*args)
      end
    end
  end
end