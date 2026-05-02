require "test_helper"

class SuggestedCategoryTest < ActiveSupport::TestCase
  test "destroying a category cascades to its suggested feeds" do
    category = SuggestedCategory.create!(name: "Tech")
    feed = Feed.create!(feed_url: "https://example.com/feed.xml", host: "example.com", title: "Example")
    SuggestedFeed.create!(suggested_category: category, feed: feed)

    assert_difference "SuggestedFeed.count", -1 do
      category.destroy!
    end
  end
end
