require "test_helper"

module FeedCrawler
  class ThrottleTest < ActiveSupport::TestCase

    def setup
      flush_redis
    end

    def test_throttled
      ENV["THROTTLED_HOSTS"] = "example.com"
      assert_not_nil Throttle.retry_after("https://www.example.com")
      difference = Throttle.retry_after("https://www.example.com") - Time.now.to_i
      assert difference > FeedCrawler::Throttle::TIMEOUT

      assert Throttle.retry_after("https://www.example.com") > Time.now.to_i
      assert_equal(nil, Throttle.retry_after("https://www.not-example.com"))
      assert_equal(nil, Throttle.retry_after(nil))
    end
  end
end