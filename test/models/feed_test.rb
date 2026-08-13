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
end
