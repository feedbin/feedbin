require "test_helper"

class SavedSearchesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @saved_search = @user.saved_searches.create(query: "\"#{@entries.first.title}\"", name: "search")
  end

  test "should show saved search" do
    login_as @user
    get :show, params: {id: @saved_search}, xhr: true
    assert_response :success
  end

  # The entry cache key also reads preview_image_record (Task 11), and
  # entry.processed_image? -- rendered for every row regardless of caching --
  # reads it too. This action builds @entries straight off the search result
  # rather than through Entry.entries_list, so without its own preload this
  # is a query per row. (A ".loaded?" assertion cannot tell a preload from an
  # N+1 that happens to run before it is checked -- processed_image? would
  # load the association either way -- so this counts queries instead.)
  #
  # Compares two distinct-feed counts rather than a fixed threshold, and
  # spreads entries across feeds rather than reusing @feeds.first: a fixed
  # number goes stale the moment a second images-backed association needs
  # its own preload (icon_image_record did -- see the show-artwork work),
  # and entries sharing one feed hide an unpreloaded icon_image_record
  # behind Rails' per-instance association cache -- the "<= 1" bumped to
  # "<= 2" for that reason still passed against a broken build, by luck of
  # every entry here having come from the same feed.
  test "should preload the preview image the entry cache key reads" do
    login_as @user
    token = "savedsearchpreviewtoken"

    few_feeds = 2.times.map { |index|
      feed = Feed.create!(feed_url: "http://savedsearchfew#{index}.example.com/feed.xml", host: "savedsearchfew#{index}.example.com", title: "Saved Search Few #{index}")
      @user.subscriptions.create!(feed: feed)
      feed
    }
    few_entries = few_feeds.map { |feed| create_entry(feed).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    few_entries.each { Search::SearchIndexStore.new.perform("Entry", it.id) }
    Search.client { it.refresh }
    saved_search = @user.saved_searches.create!(query: token, name: "preview image")

    with_few_feeds = capture_sql { get :show, params: {id: saved_search}, xhr: true }

    many_feeds = 6.times.map { |index|
      feed = Feed.create!(feed_url: "http://savedsearchmany#{index}.example.com/feed.xml", host: "savedsearchmany#{index}.example.com", title: "Saved Search Many #{index}")
      @user.subscriptions.create!(feed: feed)
      feed
    }
    many_entries = many_feeds.map { |feed| create_entry(feed).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    many_entries.each { Search::SearchIndexStore.new.perform("Entry", it.id) }
    Search.client { it.refresh }

    with_many_feeds = capture_sql { get :show, params: {id: saved_search}, xhr: true }

    assert_response :success
    assert_operator assigns(:entries).to_a.size, :>=, 8
    pattern = /FROM "images"/i
    few = with_few_feeds.count { it.match?(pattern) }
    many = with_many_feeds.count { it.match?(pattern) }
    assert_equal few, many, "the images lookup scales with the number of distinct feeds: #{few} then #{many}"
  end

  test "should accept a per_page off the query string" do
    login_as @user
    get :show, params: {id: @saved_search, per_page: "10"}, xhr: true
    assert_response :success
  end

  test "should ignore a per_page that is not a number" do
    login_as @user
    get :show, params: {id: @saved_search, per_page: "lots"}, xhr: true
    assert_response :success
  end

  test "should create saved search" do
    login_as @user
    assert_difference("SavedSearch.count", 1) do
      post :create, params: {saved_search: {query: "test", name: "test"}}, xhr: true
      assert_response :success
    end
  end

  test "should not create a saved search without a name" do
    login_as @user
    assert_no_difference("SavedSearch.count") do
      post :create, params: {saved_search: {query: "test"}}, xhr: true
    end
    assert_response :success
  end

  test "should not create a saved search Elasticsearch cannot parse" do
    login_as @user
    assert_no_difference("SavedSearch.count") do
      post :create, params: {saved_search: {query: %("unbalanced), name: "bad"}}, xhr: true
    end
    assert_response :success
  end

  test "should destroy saved search" do
    login_as @user
    assert_difference("SavedSearch.count", -1) do
      delete :destroy, params: {id: @saved_search}, xhr: true
      assert_response :success
    end
  end

  test "should update saved search" do
    login_as @user
    params = {query: "#{@saved_search.query} new", name: "#{@saved_search.name} new"}
    patch :update, params: {id: @saved_search, saved_search: params}, xhr: true
    assert_response :success
    params.each do |attribute, value|
      assert_equal value, @saved_search.reload.send(attribute.to_sym)
    end
  end
end
