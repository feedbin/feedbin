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
    entries = Entry.where(id: ids).includes(:feed).to_a

    statements = capture_sql { entries.each { entry_cache_key(_1) } }

    assert_empty favicon_queries(statements)
  end

  private

  # The lambda shared/_entries.js.erb uses to key the collection cache.
  def entry_cache_key(entry)
    ActiveSupport::Cache.expand_cache_key(EntriesHelper.entries_cache_key(entry))
  end
end
