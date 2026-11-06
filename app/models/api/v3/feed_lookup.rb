module Api
  module V3
    module FeedLookup
      def self.find(url)
        feed = Feed.xml.find_by(feed_url: url)
        if feed
          refresh(feed) if feed.standalone_request_at.blank? || feed.standalone_request_at.before?(StandaloneRetention::TTL.ago)
        else
          feed = discover(url).first
        end
        feed&.touch(:standalone_request_at)
        feed
      end

      # Any fetch failure finds nothing; unexpected ones are reported.
      def self.discover(url)
        FeedFinder.feeds(url).to_a
      rescue Feedkit::Error, HTTP::Error, Addressable::URI::InvalidURIError
        []
      rescue => exception
        ErrorService.notify(exception)
        []
      end

      def self.refresh(feed)
        FeedStatus.new.perform(feed.id)
        FeedUpdate.new.perform(feed.id)
      rescue => exception
        ErrorService.notify(exception, context: {feed_id: feed.id})
      end
    end
  end
end
