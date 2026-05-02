require "test_helper"

class Settings::NewslettersControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "GET show requires login" do
    get :show
    assert_redirected_to login_url
  end

  test "GET show renders the newsletters index view for the current user" do
    login_as @user
    get :show
    assert_response :success
  end
end
