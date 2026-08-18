require "test_helper"

class EntriesListTest < ActionController::TestCase
  tests PagesEntriesController

  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @feed.update!(feed_type: :pages)
  end

  def favicon_queries(statements)
    statements.select { it.match?(/FROM "favicons"/i) }
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
    entries = Entry.where(id: ids).includes(:feed).preload(:owned_image_records, :channel_image_record).to_a
    favicons = Favicon.for_entries(entries)

    statements = capture_sql { entries.each { entry_cache_key(it, favicons) } }

    assert_empty favicon_queries(statements)
    assert_empty statements.select { it.match?(/FROM "images"/i) },
      "the key reaches preview_image_record, so it must be preloaded"
  end

  # Non-Pages entries key on the feed's own favicon, read from the association
  # every entry-list path preloads. Without that preload this is a query per
  # row -- the N+1 the whole collection-wide approach exists to avoid.
  test "the feed-favicon branch reads the preload rather than querying" do
    plain_feed = create_feeds(@user).first
    Favicon.create!(host: plain_feed.host, url: "http://example.com/a.png")
    ids = 3.times.map { create_entry(plain_feed).id }
    entries = Entry.where(id: ids).includes(feed: [:favicon]).preload(:owned_image_records).to_a
    favicons = Favicon.for_entries(entries)

    statements = capture_sql { entries.each { entry_cache_key(it, favicons) } }

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

  # The preview row and the tweet/micropost link-preview row are both keyed
  # by the entry's own id, so the list preload fetches them in one images
  # query (owned_image_records) rather than one per reader. The full budget
  # for this load is three: the merged entry-owned query, the entry channel
  # avatars (the factory's entries carry a provider_parent_id), and the
  # feed's own icon row from Feed::ICON_PRELOADS.
  test "the entry-owned image rows load in one query" do
    ids = 3.times.map { create_entry(@feed).id }

    statements = capture_sql { Entry.where(id: ids).with_list_associations.to_a }

    images = statements.select { it.match?(/FROM "images"/i) }
    assert_equal 3, images.count,
      "expected owned + channel + feed icon, got #{images.count}:\n#{images.join("\n")}"
  end

  # The avatar a playlist entry renders belongs to the entry's own channel,
  # The avatar a playlist entry renders belongs to the entry's own channel,
  # and the touch that announces a landing avatar goes to feeds of that
  # channel -- a playlist feed of a different channel never hears it. The key
  # must read the row itself, like it does for the favicon above.
  test "storing the entry's channel avatar changes the key without touching the feed" do
    entry = create_entry(@feed)
    entry.update!(provider: :youtube, provider_id: "video1", provider_parent_id: "UCvideochannel")
    before = entry_cache_key(Entry.find(entry.id))
    feed_updated_at = @feed.reload.updated_at

    Image.create!(
      provider: :embed_icon, provider_id: "UCvideochannel",
      url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )

    refute_equal before, entry_cache_key(Entry.find(entry.id))
    assert_equal feed_updated_at.to_i, @feed.reload.updated_at.to_i
  end

  private

  # The lambda shared/_entries.js.erb uses to key the collection cache.
  private

  # The lambda shared/_entries.js.erb uses to key the collection cache.
  def entry_cache_key(entry, favicons = {})
    ActiveSupport::Cache.expand_cache_key(EntriesHelper.entries_cache_key(entry, favicons))
  end
end
