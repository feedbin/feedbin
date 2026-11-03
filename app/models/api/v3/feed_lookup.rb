module Api
  module V3
    # A feed by URL, whether or not anyone subscribes: a known feed not
    # fetched recently is refreshed first, an unknown URL is discovered.
    # Failing to reach the feed is not finding it.
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

      # The feeds at a URL. A fetch of someone else's site fails in more ways
      # than can be listed, so any failure finds nothing; the unexpected
      # ones are reported.
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
