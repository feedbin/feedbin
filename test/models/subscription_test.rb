require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "should enqueue FaviconCrawler::Finder" do
    Sidekiq::Worker.clear_all
    user = users(:ben)
    host = "example.com"
    url = URI::HTTP.build(host: host)
    feed = Feed.create(feed_url: url.to_s, site_url: url.to_s)
    assert_difference "FaviconCrawler::Finder.jobs.size", +1 do
      user.subscriptions.create(feed: feed)
      assert_equal host, FaviconCrawler::Finder.jobs.first["args"].first
    end
  end

  test "destroy clears the feed's updated entries" do
    user = users(:ben)
    subscription = user.subscriptions.first
    entry = create_entry(subscription.feed)
    UpdatedEntry.create_from_owners(user.id, entry)

    subscription.destroy

    assert_equal 0, user.updated_entries.where(feed_id: subscription.feed_id).count,
      "updated_entries are subscription-scoped and should go with the subscription"
  end

  test "create_multiple leaves the feed's own name showing when the title is left blank" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Kottke")

    subscription = Subscription.create_multiple(
      {feed.id.to_s => {"subscribe" => "1", "title" => "", "media_only" => "0"}},
      user,
      [feed.id]
    ).first

    assert_equal "Kottke", subscription.title
  end

  test "create_multiple does not discard a title the user already set" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Kottke")
    user.subscriptions.create!(feed: feed, title: "My Name For It")

    Subscription.create_multiple(
      {feed.id.to_s => {"subscribe" => "1", "title" => "", "media_only" => "0"}},
      user,
      [feed.id]
    )

    assert_equal "My Name For It", user.subscriptions.find_by(feed: feed).title
  end

  test "create_multiple survives a request with no title key" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Kottke")

    assert_nothing_raised do
      Subscription.create_multiple(
        {feed.id.to_s => {"subscribe" => "1", "media_only" => "0"}},
        user,
        [feed.id]
      )
    end
  end

  test "title falls back to the feed for a row already storing an empty string" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Kottke")
    subscription = user.subscriptions.create!(feed: feed)
    subscription.update_column(:title, "")

    assert_equal "Kottke", subscription.reload.title
  end

  test "a generated subscription's title cannot be changed" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Pages")
    subscription = user.subscriptions.create!(feed: feed, kind: :generated, title: "Pages")

    refute subscription.update(title: "Renamed"), "the model reported success for a write it means to reject"
    assert_includes subscription.errors[:title], "can not be changed"
    assert_equal "Pages", subscription.reload.title
  end

  test "an ordinary subscription's title can be changed" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Kottke")
    subscription = user.subscriptions.create!(feed: feed, title: "Kottke")

    assert subscription.update(title: "Renamed")
    assert_equal "Renamed", subscription.reload.title
  end

  test "should be media only" do
    user = users(:ben)
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex)

    feeds = {
      feed.id => {
        "title" => "title",
        "tags" => "Design",
        "subscribe" => "1",
        "media_only" => "1"
      }
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
        "media_only" => "0"
      }
    }

    Subscription.create_multiple(feeds, user, [feed.id])
    subscription = user.subscriptions.where(feed: feed).take!
    assert_not(subscription.media_only, "Subscription should be not media only")
  end
end
