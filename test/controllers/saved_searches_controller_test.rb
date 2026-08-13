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
  test "should preload the preview image the entry cache key reads" do
    login_as @user
    token = "savedsearchpreviewtoken"
    entries = 5.times.map { create_entry(@feeds.first).tap { |entry| entry.update!(title: "#{token} #{SecureRandom.hex}") } }
    entries.each { Search::SearchIndexStore.new.perform("Entry", _1.id) }
    Search.client { _1.refresh }
    saved_search = @user.saved_searches.create!(query: token, name: "preview image")

    statements = capture_sql do
      get :show, params: {id: saved_search}, xhr: true
    end

    assert_response :success
    assert_operator assigns(:entries).to_a.size, :>=, 5
    images = statements.select { _1.match?(/FROM "images"/i) }
    assert_operator images.count, :<=, 1, "one images query for the whole page: #{images.count}"
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
