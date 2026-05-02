require "test_helper"

class AppsControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
  end

  test "redirect returns root for an authenticated session" do
    login_as @user
    get :redirect
    assert_redirected_to root_url
  end

  test "redirect returns unauthorized when not signed in" do
    get :redirect
    assert_response :unauthorized
  end

  test "login signs the user in with valid HTTP basic credentials" do
    @request.env["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic.encode_credentials(@user.email, default_password)

    post :login
    assert_response :ok
  end

  test "login responds with 401 when credentials are invalid" do
    @request.env["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic.encode_credentials(@user.email, "wrong-password")

    post :login
    assert_response :unauthorized
  end

  test "login responds with 401 when no credentials are sent" do
    post :login
    assert_response :unauthorized
  end
end
