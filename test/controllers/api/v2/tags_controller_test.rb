require "test_helper"

class Api::V2::TagsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @tagging = @user.feeds.first.tag("new tag", @user, false).first
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    results = parse_json
    assert_has_keys keys, results.first
  end

  test "should update tag" do
    login_as @user
    post :update, params: {old_name: @tagging.tag.name, new_name: "#{@tagging.tag.name} New"}, format: :json
    assert_response :success

    results = parse_json
    assert_has_keys tagging_keys, results.first
  end

  test "should destroy tag" do
    login_as @user
    assert_difference "Tagging.count", -1 do
      delete :destroy, params: {name: @tagging.tag.name}, format: :json
      assert_response :success
    end
  end

  private

  def keys
    %w[id name]
  end

  def tagging_keys
    %w[id feed_id name]
  end
end
