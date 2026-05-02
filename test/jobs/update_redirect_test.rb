require "test_helper"

class UpdateRedirectTest < ActiveSupport::TestCase
  test "updates redirected_to and current_feed_url on the feed" do
    feed = Feed.create!(feed_url: "https://example.com/old", host: "example.com", title: "Test")

    UpdateRedirect.new.perform(feed.id, "https://example.com/new")

    feed.reload
    assert_equal "https://example.com/new", feed.redirected_to
    assert_equal "https://example.com/new", feed.current_feed_url
  end
end
