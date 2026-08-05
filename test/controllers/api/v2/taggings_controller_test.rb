require "test_helper"

class Api::V2::TaggingsControllerTest < ApiControllerTestCase
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

  test "should show tag" do
    login_as @user
    get :show, params: {id: @tagging}, format: :json
    assert_response :success
  end

  test "should create tagging" do
    api_content_type
    login_as @user

    assert_difference "Tagging.count", +1 do
      post :create, params: {feed_id: @user.feeds.first.id, name: "#{@tagging.tag.name} new"}, format: :json
      assert_response :success
    end
  end

  test "should reject a blank name rather than failing after deciding it succeeded" do
    api_content_type
    login_as @user

    assert_no_difference "Tagging.count" do
      post :create, params: {feed_id: @user.feeds.first.id, name: "   "}, format: :json
    end

    assert_response :bad_request
    assert parse_json["errors"].any? { |error| error.key?("name") }, parse_json.inspect
  end

  test "should reject a name that is not a string" do
    api_content_type
    login_as @user

    assert_no_difference "Tagging.count" do
      post :create, params: {feed_id: @user.feeds.first.id, name: {a: "b"}}, format: :json
    end

    assert_response :bad_request
  end

  test "should destroy tagging" do
    login_as @user

    assert_difference "Tagging.count", -1 do
      delete :destroy, params: {id: @tagging}, format: :json
      assert_response :success
    end
  end

  private

  def keys
    %w[id feed_id name]
  end
end
