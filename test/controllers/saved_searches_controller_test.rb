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

  test "should create saved search" do
    login_as @user
    assert_difference("SavedSearch.count", 1) do
      post :create, params: {saved_search: {query: "test", name: "test"}}, xhr: true
      assert_response :success
    end
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
