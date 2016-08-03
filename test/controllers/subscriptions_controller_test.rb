require 'test_helper'

class SubscriptionsControllerTest < ActionController::TestCase

  setup do
    @user = users(:ben)
    @server = DummyServer.new()
    @server.listen
  end

  teardown do
    @server.stop
  end

  test "should get index" do
    login_as @user
    get :index, format: :xml
    assert_response :success
  end

  test "should create subscription" do
    login_as @user
    xhr :post, :create, subscription: {feeds: {feed_url: @server.url("/index.html")}}
    assert_response :success
  end

end