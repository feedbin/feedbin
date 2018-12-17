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

  private

  def saved_search_keys
    %w[id name query]
  end
end
