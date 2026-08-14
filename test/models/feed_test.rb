require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "icon_url prefers the stored row and does not sign it" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      feed = create_feeds(users(:ben)).first
      feed.update!(custom_icon: "https://old.example.com/abc/show.jpg")

      assert_match "/files/icons/", feed.icon_url, "the legacy path is proxied through a signed url"

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: feed.id.to_s, feed_id: feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Feed.find(feed.id).icon_url
    end
  end

  test "icon_url is nil when the feed has no icon at all" do
    assert_nil create_feeds(users(:ben)).first.icon_url
  end

  test "channel_id comes from the parsed feed" do
    feed = Feed.create!(feed_url: "http://example.com/videos.xml", options: {"youtube_channel_id" => "UC-lHJZR3Gqxm24_Vd_AJ5Yw"})
    assert_equal "UC-lHJZR3Gqxm24_Vd_AJ5Yw", feed.channel_id
  end

  test "channel_id falls back to the feed url, and the parsed value wins" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCfromurl")
    assert_equal "UCfromurl", feed.channel_id

    feed.update!(options: {"youtube_channel_id" => "UCparsed"})
    assert_equal "UCparsed", feed.reload.channel_id
  end

  test "channel_id is nil for feeds that are not youtube" do
    assert_nil create_feeds(users(:ben)).first.channel_id
  end

  # youtube_channel_id answers a different question and keeps its own,
  # stricter rule: it drives self_url and the WebSub hub, so it requires
  # feed_url and self_url to agree. Icon resolution needs no such guard --
  # today's reverse lookup keys on the feed url alone.
  test "channel_id does not require self_url the way youtube_channel_id does" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")

    assert_nil feed.youtube_channel_id
    assert_equal "UCabc", feed.channel_id
  end
end
