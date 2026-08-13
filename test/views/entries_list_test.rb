require "test_helper"

class EntriesListTest < ActionController::TestCase
  tests PagesEntriesController

  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @feed.update!(feed_type: :pages)
  end

  def favicon_queries(statements)
    statements.select { _1.match?(/FROM "favicons"/i) }
  end

  # A Pages feed is one row holding articles from everywhere, so the favicon
  # each row needs belongs to the entry's host, not the feed's. The preload the
  # controller does cannot reach it, so the list paid for a preload it could
  # not use and then looked the rest up one at a time.
  test "the Pages list does not query favicons once per entry" do
    login_as @user
    5.times do |index|
      entry = create_entry(@feed)
      entry.update!(url: "http://site#{index}.example.com/article")
      Favicon.create!(host: "site#{index}.example.com", url: "http://example.com/f#{index}.png")
    end

    statements = capture_sql do
      get :index, params: {id: @feed.id, view: "view_all"}, format: :js, xhr: true
    end

    assert_response :success
    # Two, whatever the page size: the controller's feed preload and the
    # collection-wide lookup for the entries' own hosts.
    assert_operator favicon_queries(statements).count, :<=, 2,
      "the favicon lookups scale with the entry count: #{favicon_queries(statements).count}"
  end

  # The key enumerated the feed attributes the partial happened to use, and the
  # title was not among them -- so a publisher rename left every already
  # rendered summary showing the old name.
  test "renaming a feed changes the entry summary cache key" do
    entry = create_entry(@feed)
    before = entry_cache_key(entry)

    @feed.update!(title: "RENAMED-#{SecureRandom.hex(4)}")

    refute_equal before, entry_cache_key(Entry.find(entry.id))
  end

  test "building the cache key does not walk an association per entry" do
    ids = 5.times.map { create_entry(@feed).id }
    entries = Entry.where(id: ids).includes(:feed).preload(:preview_image_record).to_a
    favicons = Favicon.for_entries(entries)

    statements = capture_sql { entries.each { entry_cache_key(_1, favicons) } }

    assert_empty favicon_queries(statements)
    assert_empty statements.select { _1.match?(/FROM "images"/i) },
      "the key reaches preview_image_record, so it must be preloaded"
  end

  # Non-Pages entries key on the feed's own favicon, read from the association
  # every entry-list path preloads. Without that preload this is a query per
  # row -- the N+1 the whole collection-wide approach exists to avoid.
  test "the feed-favicon branch reads the preload rather than querying" do
    plain_feed = create_feeds(@user).first
    Favicon.create!(host: plain_feed.host, url: "http://example.com/a.png")
    ids = 3.times.map { create_entry(plain_feed).id }
    entries = Entry.where(id: ids).includes(feed: [:favicon]).preload(:preview_image_record).to_a
    favicons = Favicon.for_entries(entries)

    statements = capture_sql { entries.each { entry_cache_key(_1, favicons) } }

    assert_empty favicon_queries(statements)
    assert_not_nil EntriesHelper.entry_favicon(entries.first, favicons),
      "the branch must actually resolve a favicon, or this proves nothing"
  end

  # The favicon is its own row with its own timestamp. Digesting the record is
  # what lets one row update invalidate every view referencing it; the
  # alternative was TouchFeeds writing to every feed on the host -- 100,000
  # rows for a host like medium.com.
  test "changing the favicon changes the key without touching the feed" do
    entry = create_entry(@feed)
    entry.update!(url: "http://icons.example.com/article")
    favicon = Favicon.create!(host: "icons.example.com", url: "http://example.com/a.png")

    before = entry_cache_key(entry, Favicon.for_entries([entry]))
    feed_updated_at = @feed.reload.updated_at

    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    refute_equal before, entry_cache_key(entry, Favicon.for_entries([entry]))
    assert_equal feed_updated_at.to_i, @feed.reload.updated_at.to_i
  end

  test "storing a preview image changes the key" do
    entry = create_entry(@feed)
    before = entry_cache_key(entry)

    Image.create!(
      provider: :entry_preview, provider_id: entry.id.to_s, feed_id: @feed.id,
      url: "http://example.com/a.jpg", variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/a.jpg", "542x304"),
      width: 542, height: 304, bytesize: 1, placeholder_color: "aabbcc"
    )

    refute_equal before, entry_cache_key(Entry.find(entry.id))
  end

  private

  # The lambda shared/_entries.js.erb uses to key the collection cache.
  def entry_cache_key(entry, favicons = {})
    ActiveSupport::Cache.expand_cache_key(EntriesHelper.entries_cache_key(entry, favicons))
  end
end
