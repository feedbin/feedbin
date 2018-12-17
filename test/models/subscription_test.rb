require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "should enqueue FaviconFetcher" do
    Sidekiq::Worker.clear_all
    user = users(:ben)
    host = "example.com"
    url = URI::HTTP.build(host: host)
    feed = Feed.create(feed_url: url.to_s, site_url: url.to_s)
    assert_difference "FaviconFetcher.jobs.size", +1 do
      user.subscriptions.create(feed: feed)
      assert_equal host, FaviconFetcher.jobs.first["args"].first
    end
  end

  test "should be media only" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex)

    feeds = {
      feed.id => {
        "title" => "title",
        "tags" => "Design",
        "subscribe" => "1",
        "media_only" => "1",
      },
    }

    Subscription.create_multiple(feeds, user, [feed.id])
    subscription = user.subscriptions.where(feed: feed).take!
    assert(subscription.media_only, "Subscription should be media only")
  end

  test "should not media only" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex)

    feeds = {
      feed.id => {
        "title" => "title",
        "tags" => "Design",
        "subscribe" => "1",
        "media_only" => "0",
      },
    }

    Subscription.create_multiple(feeds, user, [feed.id])
    subscription = user.subscriptions.where(feed: feed).take!
    assert_not(subscription.media_only, "Subscription should be not media only")
  end
end
