require "test_helper"

module Crawler
  module Refresher
    class ThrottleTest < ActiveSupport::TestCase

      def setup
        flush_redis
      end

      def test_throttled
        ENV["THROTTLED_HOSTS"] = "example.com"
        assert     Throttle.throttled?("https://www.example.com", Time.now.to_i)
        assert_equal(false, Throttle.throttled?("https://www.example.com", Time.now.to_i - (Throttle::TIMEOUT * 2)))
        assert_equal(false, Throttle.throttled?("https://www.example.com", nil))
        assert_equal(false, Throttle.throttled?("https://www.not-example.com", Time.now.to_i))
        assert_equal(false, Throttle.throttled?(nil, nil))
      end
    end
  end
end