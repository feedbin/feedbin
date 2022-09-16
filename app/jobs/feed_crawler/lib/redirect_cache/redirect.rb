# frozen_string_literal: true

module FeedCrawler
  class RedirectCache
    class Redirect
      PERMANENT_REDIRECTS = [301, 308].to_set.freeze

      attr_reader :from, :to

      def initialize(feed_id, status:, from:, to:)
        @feed_id = feed_id
        @status = status
        @from = from
        @to = to
      end

      def permanent?
        PERMANENT_REDIRECTS.include?(@status)
      end

      def cache_key
        @cache_key ||= Digest::SHA1.hexdigest([@feed_id, @status, @from, @to].join)
      end
    end
  end
end