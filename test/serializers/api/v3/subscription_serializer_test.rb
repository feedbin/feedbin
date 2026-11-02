require "test_helper"

class Api::V3::SubscriptionSerializerTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example")
    @subscription = @user.subscriptions.create!(feed: @feed, title: "Custom")
    @feed_hash = Api::V3::FeedSerializer.new(@feed).to_h
  end

  test "serializes a subscription with ids by default" do
    json = Api::V3::SubscriptionSerializer.new(@subscription, tags: [[4, "Apple"], [9, "News"]]).to_h

    assert_equal %i[object id created_at title custom_title feed_id tag_ids preferences], json.keys
    assert_equal "subscription", json[:object]
    assert_equal @subscription.id, json[:id]
    assert_equal @subscription.created_at.utc.iso8601, json[:created_at]
    assert_equal "Custom", json[:title]
    assert_equal "Custom", json[:custom_title]
    assert_equal @feed.id, json[:feed_id]
    assert_equal [4, 9], json[:tag_ids]
    assert_equal({muted: false, media_only: false, show_updates: true}, json[:preferences])
  end

  test "expands the feed and tags when asked" do
    json = Api::V3::SubscriptionSerializer.new(@subscription, tags: [[4, "Apple"]], feed: @feed_hash, expand: %w[feed tags]).to_h

    assert_equal %i[object id created_at title custom_title feed_id tag_ids preferences feed tags], json.keys
    assert_equal @feed_hash, json[:feed]
    assert_equal [{object: "tag", id: 4, name: "Apple"}], json[:tags]
  end

  test "falls back to the feed's title when none is set" do
    @subscription.update!(title: nil)

    json = Api::V3::SubscriptionSerializer.new(@subscription, tags: []).to_h

    assert_equal "Example", json[:title]
    assert_nil json[:custom_title]
    assert_equal [], json[:tag_ids]
  end
end
