require "test_helper"

class FeedStatusTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  test "should create page" do
    feed = feeds(:daring_fireball)
    redirect = "http://example.com"
    Sidekiq.redis do |client|
      client.hset feed.redirect_key, "to", redirect
    end
    FeedStatus.new.perform(feed.id)
    assert_equal(redirect, feed.reload.current_feed_url)
  end
end
