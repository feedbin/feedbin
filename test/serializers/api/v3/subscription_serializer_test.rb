require "test_helper"

class Api::V3::SubscriptionSerializerTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example")
    @subscription = @user.subscriptions.create!(feed: @feed, title: "Custom")
    @feed_hash = Api::V3::FeedSerializer.new(@feed).to_h
  end

  test "serializes a subscription with its overrides, feed and tags" do
    json = Api::V3::SubscriptionSerializer.new(@subscription, feed: @feed_hash, tags: [[4, "Apple"], [9, "News"]]).to_h

    assert_equal %i[object id created_at title custom_title feed preferences tags], json.keys
    assert_equal "subscription", json[:object]
    assert_equal @subscription.id, json[:id]
    assert_equal @subscription.created_at.utc.iso8601, json[:created_at]
    assert_equal "Custom", json[:title]
    assert_equal "Custom", json[:custom_title]
    assert_equal @feed_hash, json[:feed]
    assert_equal({muted: false, media_only: false, show_updates: true}, json[:preferences])
    assert_equal [{object: "tag", id: 4, name: "Apple"}, {object: "tag", id: 9, name: "News"}], json[:tags]
  end

  test "falls back to the feed's title when none is set" do
    @subscription.update!(title: nil)

    json = Api::V3::SubscriptionSerializer.new(@subscription, feed: @feed_hash, tags: []).to_h

    assert_equal "Example", json[:title]
    assert_nil json[:custom_title]
    assert_equal [], json[:tags]
  end
end
