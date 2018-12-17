require "test_helper"

class SiteControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get index" do
    login_as @user
    get :index
    assert_response :success
  end

  test "should get headers" do
    login_as @user
    get :index
    assert_response :success
  end
end
