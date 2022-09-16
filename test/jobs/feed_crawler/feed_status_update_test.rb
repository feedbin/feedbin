require "test_helper"

module FeedCrawler
  class FeedStatusUpdateTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_clear_status
      feed_id = 1
      FeedStatus.new(feed_id).error!(Exception.new)
      refute FeedStatus.new(feed_id).ok?, "ok? should be false."
      FeedStatusUpdate.new.perform(feed_id)
      assert FeedStatus.new(feed_id).ok?, "ok? should be true."
    end

    def test_should_record_error
      feed_id = 1
      exception = Exception.new
      formatted_exception = JSON.dump({date: Time.now.to_i, class: exception.class, message: exception.message, status: nil})
      FeedStatusUpdate.new.perform(feed_id, formatted_exception)
      status = FeedStatus.new(feed_id)
      refute status.ok?, "ok? should be false."
      assert_equal exception.class.name, status.attempt_log.first["class"]
    end
  end
end