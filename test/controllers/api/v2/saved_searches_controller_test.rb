require "test_helper"

class Api::V2::SavedSearchesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @entry = @entries.first
    @saved_search = @user.saved_searches.create(query: "\"#{@entry.title}\"", name: "search")
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    records = parse_json
    assert_has_keys saved_search_keys, records.first
  end

  test "should show saved search" do
    login_as @user
    get :show, params: {id: @saved_search}, format: :json
    assert_response :success
    assert_equal Set.new([@entry.id]), Set.new(parse_json)

    get :show, params: {id: @saved_search, include_entries: "true"}, format: :json
    assert_response :success
    assert_equal_ids [@entry], parse_json
  end

  test "should create saved search" do
    api_content_type
    login_as @user
    assert_difference("SavedSearch.count", 1) do
      post :create, params: {saved_search: {query: "test", name: "test"}}, format: :json
      assert_response :success
    end
  end

  test "should destroy saved search" do
    login_as @user
    assert_difference("SavedSearch.count", -1) do
      delete :destroy, params: {id: @saved_search}, format: :json
      assert_response :success
    end
  end

  test "should update saved search" do
    api_content_type
    login_as @user
    params = {query: "#{@saved_search.query} new", name: "#{@saved_search.name} new"}
    patch :update, params: {id: @saved_search, saved_search: params}, format: :json
    assert_response :success
    params.each do |attribute, value|
      assert_equal value, @saved_search.reload.send(attribute.to_sym)
    end
  end

  test "index returns empty array when user has no saved searches" do
    @user.saved_searches.destroy_all
    login_as @user

    get :index, format: :json
    assert_response :success
    assert_equal [], assigns(:saved_searches)
  end

  test "show returns forbidden when saved search does not belong to user" do
    other_search = users(:ben).saved_searches.create!(query: "x", name: "x")
    login_as @user

    get :show, params: {id: other_search.id}, format: :json
    assert_response :forbidden
  end

  test "destroy returns forbidden when saved search does not belong to user" do
    other_search = users(:ben).saved_searches.create!(query: "x", name: "x")
    login_as @user

    assert_no_difference "SavedSearch.count" do
      delete :destroy, params: {id: other_search.id}, format: :json
    end
    assert_response :forbidden
  end

  test "update returns forbidden when saved search does not belong to user" do
    other_search = users(:ben).saved_searches.create!(query: "x", name: "x")
    login_as @user

    patch :update,
      params: {id: other_search.id, saved_search: {query: "new", name: "new"}},
      format: :json
    assert_response :forbidden

    other_search.reload
    assert_equal "x", other_search.query
  end

  test "show returns empty json when no entries match" do
    empty_search = @user.saved_searches.create!(query: "verynonexistentquerystring12345", name: "empty")
    login_as @user

    get :show, params: {id: empty_search.id}, format: :json
    assert_response :success
    assert_equal [], parse_json
  end

  private

  def saved_search_keys
    %w[id name query]
  end
end
