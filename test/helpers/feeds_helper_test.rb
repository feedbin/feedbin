require "test_helper"

class FeedsHelperTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = create_feeds(@user).first
  end

  def loaded_feeds
    @user.feeds.where(id: @feed.id).includes(:favicon).to_a
  end

  # The sidebar renders a FaviconComponent per feed, and a favicon is its own
  # row with its own timestamp. The key used the feed record as a proxy for it,
  # which only worked because TouchFeeds wrote to the feed.
  test "the feeds key changes when a favicon changes, without touching the feed" do
    favicon = Favicon.create!(host: @feed.host, url: "http://example.com/a.png")

    before = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_feeds_cache_key(loaded_feeds))
    feed_updated_at = @feed.reload.updated_at

    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    after = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_feeds_cache_key(loaded_feeds))

    refute_equal before, after
    assert_equal feed_updated_at.to_i, @feed.reload.updated_at.to_i
  end

  test "the tags key changes when a tagged feed's favicon changes" do
    @feed.tag("News", @user)
    favicon = Favicon.create!(host: @feed.host, url: "http://example.com/a.png")

    before = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_tags_cache_key(@user.tag_group))

    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    after = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_tags_cache_key(@user.tag_group))

    refute_equal before, after
  end

  # Both @feeds and tag_group's feeds are already includes(:favicon), so this
  # costs nothing -- but only as long as the key reads what was preloaded.
  test "the feeds key does not query favicons when they are preloaded" do
    Favicon.create!(host: @feed.host, url: "http://example.com/a.png")
    feeds = loaded_feeds

    statements = capture_sql { FeedsHelper.sidebar_feeds_cache_key(feeds) }

    assert_empty statements.select { _1.match?(/FROM "favicons"/i) }
  end
end
