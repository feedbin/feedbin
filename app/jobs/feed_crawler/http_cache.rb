# frozen_string_literal: true

module Crawler
  module Refresher
    class HttpCache
      def initialize(feed_id)
        @feed_id = feed_id
      end

      def save(response)
        data = {
          etag:          response.etag,
          last_modified: response.last_modified,
          checksum:      response.checksum
        }
        Cache.write(cache_key, data, options: {expires_in: 8 * 60 * 60})
      end

      def etag
        cached[:etag]
      end

      def last_modified
        cached[:last_modified]
      end

      def checksum
        cached[:checksum]
      end

      def cached
        @cached ||= begin
          Cache.read(cache_key)
        end
      end

      def cache_key
        "refresher_http_#{@feed_id}"
      end
    end
  end
end