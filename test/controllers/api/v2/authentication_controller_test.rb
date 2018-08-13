require "test_helper"

class Api::V2::AuthenticationControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should authenticate" do
    login_as @user
    get :index
    assert_response :success
  end

  test "should not authenticate" do
    get :index
    assert_response :unauthorized
  end
end
