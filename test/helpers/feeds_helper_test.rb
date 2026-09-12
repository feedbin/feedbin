require "test_helper"

class FeedsHelperTest < ActiveSupport::TestCase
  include FeedsHelper

  setup do
    @user = users(:ben)
    @feed = create_feeds(@user).first
  end

  def loaded_feeds
    @user.feeds.where(id: @feed.id).includes(*Feed::ICON_PRELOADS).to_a
  end

  # Simulates the pipeline storing new bytes for the host: a new object at a
  # new path. That is the only write that moves images.updated_at.
  def replace_bytes(row)
    row.update!(
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")
    )
  end

  # A favicon is its own row with its own timestamp; the key must digest
  # it, not use the feed record as a proxy.
  test "the feeds key changes when the favicon row changes, without touching the feed" do
    row = create_favicon_row(@feed.host)

    before = ActiveSupport::Cache.expand_cache_key(sidebar_feeds_cache_key(loaded_feeds))
    feed_updated_at = @feed.reload.updated_at

    travel 1.minute do
      replace_bytes(row)
    end

    after = ActiveSupport::Cache.expand_cache_key(sidebar_feeds_cache_key(loaded_feeds))

    refute_equal before, after
    assert_equal feed_updated_at.to_i, @feed.reload.updated_at.to_i
  end

  test "the tags key changes when a tagged feed's favicon row changes" do
    @feed.tag("News", @user)
    row = create_favicon_row(@feed.host)

    before = ActiveSupport::Cache.expand_cache_key(sidebar_tags_cache_key(@user.tag_group))

    travel 1.minute do
      replace_bytes(row)
    end

    after = ActiveSupport::Cache.expand_cache_key(sidebar_tags_cache_key(@user.tag_group))

    refute_equal before, after
  end

  # favicons fallback: a host with no images row still digests its legacy
  # row, so the sidebar keeps invalidating for it until the backfill lands.
  test "the feeds key digests the favicons row when no images row exists" do
    favicon = Favicon.create!(host: @feed.host, url: "http://example.com/a.png")

    before = ActiveSupport::Cache.expand_cache_key(sidebar_feeds_cache_key(loaded_feeds))
    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    refute_equal before, ActiveSupport::Cache.expand_cache_key(sidebar_feeds_cache_key(loaded_feeds))
  end

  # Both @feeds and tag_group's feeds are already includes(*ICON_PRELOADS),
  # so this costs nothing -- but only as long as the key reads what was
  # preloaded.
  test "the feeds key does not query when the icon rows are preloaded" do
    create_favicon_row(@feed.host)
    feeds = loaded_feeds

    statements = capture_sql { sidebar_feeds_cache_key(feeds) }

    assert_empty statements.select { it.match?(/FROM "favicons"|FROM "images"/i) }
  end

  # Tag#user_feeds is an attr_accessor populated by User#tag_group, not an
  # association -- a structurally different path to the favicon than the
  # feeds key above. Assert the key actually carries the row too, so this
  # can't pass vacuously on an empty tag list.
  test "the tags key does not query when the icon rows are preloaded" do
    @feed.tag("News", @user)
    row = create_favicon_row(@feed.host)
    tags = @user.tag_group

    key = nil
    statements = capture_sql { key = sidebar_tags_cache_key(tags) }

    assert_empty statements.select { it.match?(/FROM "favicons"|FROM "images"/i) }
    _, _, _, favicons, _ = key
    assert_includes favicons, row
  end
end
