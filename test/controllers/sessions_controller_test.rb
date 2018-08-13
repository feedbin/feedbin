require "test_helper"

class SessionsControllerTest < ActionController::TestCase
  include SessionsHelper

  setup do
    @user = users(:ben)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create new session" do
    post :create, params: {email: @user.email, password: default_password}
    assert signed_in?
    assert_redirected_to root_url
  end

  test "should destroy session" do
    login_as @user
    delete :destroy
    assert_redirected_to root_url
  end

  test "should get refresh" do
    login_as @user
    get :refresh
    assert_response :success
  end
end
