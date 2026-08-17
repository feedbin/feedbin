require "test_helper"

class EntriesSearchControllerTest < ActionController::TestCase
  tests EntriesController  # explicitly declare controller

  setup do
    @user = users(:ben)
    @entry = create_entry(@user.feeds.first)
  end

  test "should get search" do
    login_as @user
    # A unique token: search index contents survive across tests in a run, so
    # a Faker sentence can collide with a stale document from another test.
    @entry.update!(title: "searchtoken #{SecureRandom.hex}")
    reindex_search
    get :search, params: {query: "\"#{@entry.title}\""}, xhr: true
    assert_response :success
    assert_equal 1, assigns(:page_query).total_entries
  end

  # shared/_entries.js.erb is the one template every entry list renders, and it
  # reaches for the feed's favicon. Every other caller preloads it; the two
  # search paths stopped at the feed.
  test "search results preload the favicon the shared template renders" do
    login_as @user
    token = "faviconpreloadtoken"
    # One feed per entry: the preloader shares a Feed instance between entries
    # of the same feed, so the association cache hides the extra queries when
    # every result comes from one source.
    feeds = 5.times.map { |index|
      feed = Feed.create!(feed_url: "http://preload#{index}.example.com/feed.xml", host: "preload#{index}.example.com", title: "Feed #{index}")
      @user.subscriptions.create!(feed: feed)
      feed
    }
    entries = feeds.map { create_entry(it).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    entries.each { Search::SearchIndexStore.new.perform("Entry", it.id) }
    Search.client { it.refresh }

    statements = capture_sql do
      get :search, params: {query: token}, xhr: true
    end

    assert_response :success
    assert_operator assigns(:entries).to_a.size, :>=, 5
    favicons = statements.select { it.match?(/FROM "favicons"/i) }
    assert_operator favicons.count, :<=, 1, "one favicon query per result: #{favicons.count}"
  end

  # The entry cache key also reads preview_image_record (Task 11), and
  # entry.processed_image? -- rendered for every row regardless of caching --
  # reads it too. This path builds @entries straight off the search result
  # rather than through Entry.entries_list, so without its own preload this
  # is a query per row, same shape as the favicon test above. (A ".loaded?"
  # assertion cannot tell a preload from an N+1 that happens to run before it
  # is checked -- processed_image? would load the association either way --
  # so this counts queries instead, like the favicon guard above does.)
  #
  # Compares two distinct-feed counts rather than a fixed threshold, and
  # spreads entries across feeds rather than reusing @user.feeds.first: a
  # fixed number goes stale the moment a second images-backed association
  # needs its own preload (icon_image_record did -- see the show-artwork
  # work), and entries sharing one feed hide an unpreloaded icon_image_record
  # behind Rails' per-instance association cache, the same trap the favicon
  # test above already sidesteps for the same reason.
  test "search results preload the preview image entries render" do
    login_as @user
    token = "previewimagepreloadtoken"

    few_feeds = 2.times.map { |index|
      feed = Feed.create!(feed_url: "http://previewfew#{index}.example.com/feed.xml", host: "previewfew#{index}.example.com", title: "Preview Few #{index}")
      @user.subscriptions.create!(feed: feed)
      feed
    }
    few_entries = few_feeds.map { |feed| create_entry(feed).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    few_entries.each { Search::SearchIndexStore.new.perform("Entry", it.id) }
    Search.client { it.refresh }

    with_few_feeds = capture_sql { get :search, params: {query: token}, xhr: true }

    many_feeds = 6.times.map { |index|
      feed = Feed.create!(feed_url: "http://previewmany#{index}.example.com/feed.xml", host: "previewmany#{index}.example.com", title: "Preview Many #{index}")
      @user.subscriptions.create!(feed: feed)
      feed
    }
    many_entries = many_feeds.map { |feed| create_entry(feed).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    many_entries.each { Search::SearchIndexStore.new.perform("Entry", it.id) }
    Search.client { it.refresh }

    with_many_feeds = capture_sql { get :search, params: {query: token}, xhr: true }

    assert_response :success
    assert_operator assigns(:entries).to_a.size, :>=, 8
    pattern = /FROM "images"/i
    few = with_few_feeds.count { it.match?(pattern) }
    many = with_many_feeds.count { it.match?(pattern) }
    assert_equal few, many, "the images lookup scales with the number of distinct feeds: #{few} then #{many}"
  end

  test "should handle complex query with multiple conditions" do
    @entry.update!(title: "Cat Story", content: "About cats", published: Date.parse("2023-06-15"))
    reindex_search
    login_as @user
    get :search, params: {query: "cats is:unread sort:desc published:>2023-01-01"}, xhr: true
    assert_response :success
    assert_equal(@entry, assigns(:entries).first)
  end

  test "should handle query with boolean operators and ranges" do
    @entry.update!(title: "", content: "")
    reindex_search
    @user.starred_entries.create!(entry: @entry)
    login_as @user
    get :search, params: {query: "dogs OR is:starred"}, xhr: true
    assert_response :success
    assert_equal(@entry, assigns(:entries).first)
  end

  test "should handle query with tag groups" do
    @entry.update!(title: "Tagged Story", content: "Content", updated: Date.parse("2023-08-15"))
    reindex_search

    tag = Tag.create!(name: "Tag")
    @user.taggings.create!(tag: tag, feed: @entry.feed)

    login_as @user
    get :search, params: {query: "tagged tag_id:#{tag.id} word_count:[1 TO 2]"}, xhr: true
    assert_response :success
    assert_equal(@entry, assigns(:entries).first)
  end

  test "should handle query with date ranges" do
    @entry.update!(title: "Tagged Story", content: "Content", updated_at: Date.parse("2023-08-15"), published: Date.parse("2023-08-15"))
    reindex_search

    tag = Tag.create!(name: "Tag")
    @user.taggings.create!(tag: tag, feed: @entry.feed)

    login_as @user
    get :search, params: {query: "updated:[2023-06-01 TO 2023-12-31]"}, xhr: true
    assert_response :success
    assert_equal(@entry, assigns(:entries).first)

    get :search, params: {query: "published:[2023-06-01 TO 2023-12-31]"}, xhr: true
    assert_equal(@entry, assigns(:entries).first)
  end

  test "should handle exact title search" do
    @entry.update!(title: "Exact Title Search", content: "Exact Content Search", author: nil)
    reindex_search
    login_as @user
    get :search, params: {query: "title_exact:\"Exact Title Search\""}, xhr: true
    assert_equal(@entry, assigns(:entries).first)

    get :search, params: {query: "content.exact:\"Exact Content Search\""}, xhr: true
    assert_equal(@entry, assigns(:entries).first)

    get :search, params: {query: "body:\"Exact Content Search\""}, xhr: true
    assert_equal(@entry, assigns(:entries).first)

    get :search, params: {query: "_missing_:author"}, xhr: true
    assert_equal(@entry, assigns(:entries).first)
  end

  private

  def reindex_search
    Search::SearchIndexStore.new.perform("Entry", @entry.id)
    Search.client { it.refresh }
  end
end
