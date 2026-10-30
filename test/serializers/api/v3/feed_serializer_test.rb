require "test_helper"

class Api::V3::FeedSerializerTest < ActiveSupport::TestCase
  setup do
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example", site_url: "https://example.com", options: {"description" => "<p>About <b>things</b></p>"})
  end

  test "serializes a healthy feed" do
    json = serialize(posts_per_week: 2.5)

    assert_equal %i[object id title description kind feed_url site_url hostname images health stats channel_id list_unsubscribe], json.keys
    assert_equal "About things", json[:description]
    assert_equal "xml", json[:kind]
    assert_equal "example.com", json[:hostname]
    assert_equal({favicon: nil, touch_icon: nil, icon: nil}, json[:images])
    assert_equal "ok", json[:health][:status]
    assert_nil json[:health][:message]
    assert_equal({subscriber_count: 0, posts_per_week: 2.5}, json[:stats])
  end

  test "finds the favicon and touch icon by host and the channel's picture" do
    @feed.update_column(:channel_id, "UCBJycsmduvYEL83R_U4JriQ")
    create_favicon_row("example.com")
    create_favicon_row("example.com", provider: :website_touch_icon)
    create_image_row(provider: :embed_icon, provider_id: "UCBJycsmduvYEL83R_U4JriQ", kind: :avatar)

    json = serialize

    assert_equal "site_icon", json[:images][:favicon][:kind]
    assert_equal "site_icon", json[:images][:touch_icon][:kind]
    assert_equal "avatar", json[:images][:icon][:kind]
    assert_equal "UCBJycsmduvYEL83R_U4JriQ", json[:channel_id]
  end

  test "reports a feed that keeps failing" do
    @feed.stub(:crawl_error?, true) do
      @feed.stub(:dead?, true) do
        health = Api::V3::FeedSerializer.new(@feed, posts_per_week: 0).to_h[:health]
        assert_equal "dead", health[:status]
        assert health[:message].present?
      end
    end
  end

  private

  def serialize(posts_per_week: 0.0)
    feed = Feed.preload(*Feed::ICON_PRELOADS, :touch_icon_image_record).find(@feed.id)
    Api::V3::FeedSerializer.new(feed, posts_per_week: posts_per_week).to_h
  end
end
