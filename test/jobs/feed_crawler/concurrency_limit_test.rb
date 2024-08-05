require "test_helper"

module FeedCrawler
  class ConcurrencyLimitTest < ActiveSupport::TestCase

    def test_limits
      result1 = nil
      result2 = nil

      t1 = Thread.new do
        result1 = FeedCrawler::ConcurrencyLimit.acquire("https://example.com", timeout: 5) do
          sleep(0.1)
          true
        end
      end

      t2 = Thread.new do
        assert_raises(FeedCrawler::ConcurrencyLimit::TimeoutError) do
          result2 = FeedCrawler::ConcurrencyLimit.acquire("https://example.com", timeout: 0.01) do
            true
          end
        end
      end

      [t1, t2].each(&:join)

      assert result1
      refute result2
    end

    def test_no_limits
      result1 = nil
      result2 = nil

      t1 = Thread.new do
        FeedCrawler::ConcurrencyLimit.acquire("https://example2.com", timeout: 5) do
          sleep(0.1)
          true
        end
      end

      t2 = Thread.new do
        FeedCrawler::ConcurrencyLimit.acquire("https://example2.com", timeout: 0.01) do
          true
        end
      end

      [t1, t2].each(&:join)
    end
  end
end