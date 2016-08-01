require 'test_helper'

class SavedSearchesControllerTest < ActionController::TestCase

  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @saved_search = @user.saved_searches.create(query: "\"#{@entries.first.title}\"", name: 'search')
  end

  test "should show saved search" do
    login_as @user
    xhr :get, :show, id: @saved_search
    assert_response :success
  end

  test "should create saved search" do
    login_as @user
    assert_difference('SavedSearch.count', 1) do
      xhr :post, :create, saved_search: {query: 'test', name: 'test'}
      assert_response :success
    end
  end

  test "should destroy saved search" do
    login_as @user
    assert_difference('SavedSearch.count', -1) do
      xhr :delete, :destroy, id: @saved_search
      assert_response :success
    end
  end

  test "should update saved search" do
    login_as @user
    params = {query: "#{@saved_search.query} new", name: "#{@saved_search.name} new"}
    xhr :patch, :update, id: @saved_search, saved_search: params
    assert_response :success
    params.each do |attribute, value|
      assert_equal value, @saved_search.reload.send(attribute.to_sym)
    end
  end

end
