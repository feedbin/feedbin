require "test_helper"

class TagsControllerTest < ActionController::TestCase
  def setup
    @user = users(:ben)
    @tag = @user.feeds.first.tag("Tag", @user).first.tag
  end

  test "should get index" do
    login_as @user
    get :index, params: {query: @tag.name}, format: :json
    assert_response :success
    data = JSON.parse(@response.body)
    assert_kind_of Array, data["suggestions"]
    ["value", "data"].each do |key|
      assert data["suggestions"].first.key?(key)
    end
  end

  test "should get index with no query" do
    login_as @user

    get :index, format: :json

    assert_response :success
    assert_includes JSON.parse(@response.body)["suggestions"].map { it["value"] }, @tag.name
  end

  test "should get index when query is not a string" do
    login_as @user

    get :index, params: {query: ["x"]}, format: :json

    assert_response :success
  end

  test "should show tag" do
    login_as @user
    get :show, params: {id: @tag}, xhr: true
    assert_response :success
  end

  test "should update tag" do
    login_as @user
    assert_difference "Tag.count", +1 do
      post :update, params: {id: @tag, tag: {name: "#{@tag.name} New"}}, xhr: true
      assert_response :success
    end
  end

  test "should not fail when the tag key is missing" do
    login_as @user
    assert_no_difference "Tag.count" do
      post :update, params: {id: @tag}, xhr: true
    end
    assert_response :success
  end

  test "should not fail when the new name is empty after normalising" do
    login_as @user
    assert_no_difference "Tag.count" do
      post :update, params: {id: @tag, tag: {name: " , "}}, xhr: true
    end
    assert_response :success
  end

  test "should destroy tag" do
    login_as @user
    assert_difference "Tagging.count", -1 do
      delete :destroy, params: {id: @tag}, xhr: true
      assert_response :success
    end
  end
end
