module FeedCrawler
  class ConcurrencyLimit

    class TimeoutError < StandardError; end

    LIMITS = FeedbinUtils.key_value_parser(ENV["HOST_CONCURRENCY_LIMIT"]) do |limit|
      Concurrent::Semaphore.new(limit.to_i)
    end

    def initialize(feed_url)
      @feed_url = feed_url
    end

    def self.acquire(feed_url, timeout:, &block)
      new(feed_url).acquire(timeout: timeout, &block)
    end

    def acquire(timeout:, &block)
      return yield unless LIMITS.key?(host)
      LIMITS[host].try_acquire(1, timeout) do
        return yield
      end
      raise TimeoutError.new("Timed out acquiring lock for #{host}. Waited #{timeout} seconds.")
    end

    def host
      Addressable::URI.heuristic_parse(@feed_url).host
    rescue
      nil
    end
  end
end
