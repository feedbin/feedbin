require "test_helper"

class DiscoveredFeedTest < ActiveSupport::TestCase
  test "set_host parses host from site_url before create" do
    feed = DiscoveredFeed.create!(site_url: "https://Example.com/path")
    assert_equal "example.com", feed.host
  end

  test "set_host downcases the host" do
    feed = DiscoveredFeed.create!(site_url: "https://EXAMPLE.com")
    assert_equal "example.com", feed.host
  end

  test "set_host falls back to heuristic parsing for bare hostnames" do
    feed = DiscoveredFeed.create!(site_url: "example.com")
    assert_equal "example.com", feed.host
  end

  test "set_host leaves host nil when site_url is missing" do
    feed = DiscoveredFeed.create!(site_url: nil)
    assert_nil feed.host
  end
end
