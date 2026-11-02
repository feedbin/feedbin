module Api
  module V3
    # An OPML import and each item's outcome. Feedbin does not record which
    # subscription an item became, so subscription_id is the user's
    # subscription to the item's feed URL, when there is one.
    class ImportSerializer
      def initialize(import)
        @import = import
      end

      def to_h
        items = @import.import_items.sort_by(&:id)
        subscription_ids = subscription_ids(items.select(&:complete?).map(&:feed_url))
        {
          object: "import",
          id: @import.id,
          status: items.any?(&:pending?) ? "pending" : "complete",
          items: items.map { item(_1, subscription_ids) },
          created_at: @import.created_at.utc.iso8601
        }
      end

      private

      def item(item, subscription_ids)
        {
          title: item.title,
          feed_url: item.feed_url,
          status: item.status,
          subscription_id: item.complete? ? subscription_ids[item.feed_url] : nil,
          message: message(item)
        }
      end

      # The importer stores the exception it hit, or nothing when the URL
      # simply had no feed.
      def message(item)
        return unless item.failed? || item.fixable?
        ImportItem::ERRORS[item.error_class] || item.error_message.presence || "No feed found."
      end

      def subscription_ids(feed_urls)
        return {} if feed_urls.empty?
        @import.user.subscriptions.joins(:feed).where(feeds: {feed_url: feed_urls}).pluck("feeds.feed_url", "subscriptions.id").to_h
      end
    end
  end
end
