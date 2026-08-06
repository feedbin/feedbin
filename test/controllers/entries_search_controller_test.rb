require "test_helper"

class EntriesSearchControllerTest < ActionController::TestCase
  tests EntriesController  # explicitly declare controller

  setup do
    @user = users(:ben)
    @entry = create_entry(@user.feeds.first)
  end

  test "should get search" do
    login_as @user
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
    entries = feeds.map { create_entry(_1).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    entries.each { Search::SearchIndexStore.new.perform("Entry", _1.id) }
    Search.client { _1.refresh }

    statements = capture_sql do
      get :search, params: {query: token}, xhr: true
    end

    assert_response :success
    assert_operator assigns(:entries).to_a.size, :>=, 5
    favicons = statements.select { _1.match?(/FROM "favicons"/i) }
    assert_operator favicons.count, :<=, 1, "one favicon query per result: #{favicons.count}"
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
    Search.client { _1.refresh }
  end
end
