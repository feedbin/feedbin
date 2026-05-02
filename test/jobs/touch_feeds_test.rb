require "test_helper"

class TouchFeedsTest < ActiveSupport::TestCase
  test "updates updated_at on feeds with the matching host" do
    matching_a = Feed.create!(feed_url: "https://example.com/a", host: "example.com", title: "A", updated_at: 1.year.ago)
    matching_b = Feed.create!(feed_url: "https://example.com/b", host: "example.com", title: "B", updated_at: 1.year.ago)
    other = Feed.create!(feed_url: "https://other.example.com/c", host: "other.example.com", title: "C", updated_at: 1.year.ago)

    TouchFeeds.new.perform("example.com")

    assert_in_delta Time.now, matching_a.reload.updated_at, 5
    assert_in_delta Time.now, matching_b.reload.updated_at, 5
    assert_operator other.reload.updated_at, :<, 1.month.ago
  end

  test "is a no-op when no feeds match the host" do
    assert_nothing_raised do
      TouchFeeds.new.perform("nonexistent.example")
    end
  end
end
