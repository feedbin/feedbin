require 'test_helper'

class SubscriptionTest < ActiveSupport::TestCase

  test "should enqueue EmailUnsubscribe" do
    user = users(:ben)
    subscription = user.subscriptions.first
    assert_difference "EmailUnsubscribe.jobs.size", +1 do
      subscription.destroy
    end
  end

  test "should enqueue FaviconFetcher" do
    user = users(:ben)
    host = "example.com"
    url = URI::HTTP.build(host: host)
    feed = Feed.create(feed_url: url.to_s, site_url: url.to_s)
    assert_difference "FaviconFetcher.jobs.size", +1 do
      user.subscriptions.create(feed: feed)
      assert_equal host, FaviconFetcher.jobs.first["args"].first
    end
  end


end
