require "test_helper"

class Admin::FeedsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @user.update!(admin: true) if @user.respond_to?(:admin=)
  end

  test "GET index renders without a query" do
    login_as @user
    get :index
    assert_response :success
  end

  test "GET index with a non-numeric query takes the feed_url branch" do
    login_as @user
    get :index, params: {q: @feed.feed_url}
    assert_response :success
  end

  test "GET index with a numeric query takes the id branch" do
    login_as @user
    get :index, params: {q: @feed.id.to_s}
    assert_response :success
  end
end
