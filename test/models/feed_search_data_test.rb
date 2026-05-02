require "test_helper"

class FeedSearchDataTest < ActiveSupport::TestCase
  setup do
    @feed = Feed.create!(
      feed_url: "https://example.com/feed.xml",
      site_url: "https://example.com/",
      title: "Example",
      meta_title: "Meta",
      meta_description: "Meta desc",
      options: {"description" => "Hello"}
    )
  end

  test "to_h includes feed core attributes" do
    hash = FeedSearchData.new(@feed).to_h

    assert_equal @feed.id, hash[:id]
    assert_equal "Example", hash[:title]
    assert_equal "Meta", hash[:meta_title]
    assert_equal "Meta desc", hash[:meta_description]
    assert_equal "Hello", hash[:description]
  end

  test "format_url splits and excludes generic url tokens" do
    data = FeedSearchData.new(@feed)
    parts = data.format_url("https://www.example.com/path/index.xml")

    refute_includes parts, "https:"
    refute_includes parts, "www"
    refute_includes parts, "com"
    refute_includes parts, "index"
    refute_includes parts, "xml"
    assert_includes parts, "example"
    assert_includes parts, "path"
  end

  test "format_url handles a nil url without raising" do
    data = FeedSearchData.new(@feed)
    assert_equal [], data.format_url(nil)
  end

  test "description returns nil when options is missing the key" do
    @feed.update!(options: {})
    assert_nil FeedSearchData.new(@feed).description
  end
end
