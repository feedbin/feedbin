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

  test "should destroy tag" do
    login_as @user
    assert_difference "Tagging.count", -1 do
      delete :destroy, params: {id: @tag}, xhr: true
      assert_response :success
    end
  end

  test "should get edit" do
    login_as @user
    get :edit, params: {id: @tag}, xhr: true
    assert_response :success
  end

  test "should not expose a tag the user has no tagging for" do
    stranger = users(:ann)
    refute_includes stranger.feed_tags.map(&:id), @tag.id

    login_as stranger

    get :edit, params: {id: @tag}, xhr: true
    assert_response :not_found
    refute_includes @response.body, @tag.name

    get :show, params: {id: @tag}, xhr: true
    assert_response :not_found

    assert_no_difference "Tag.count" do
      post :update, params: {id: @tag, tag: {name: "Hijacked"}}, xhr: true
    end
    assert_response :not_found

    delete :destroy, params: {id: @tag}, xhr: true
    assert_response :not_found
  end
end
