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

  # sign_out resets the session and sign_in did not, so anything written to a
  # visitor's session before login survived the privilege transition.
  test "signing in discards session data planted before authentication" do
    session[:planted] = "attacker-value"

    post :create, params: {email: @user.email, password: default_password}

    assert_nil session[:planted]
  end

  test "signing in still honours the location stored before login" do
    session[:return_to] = settings_account_url

    post :create, params: {email: @user.email, password: default_password}

    assert_redirected_to settings_account_url
  end

  test "should get new on the api subdomain" do
    # SessionsHelper is mixed into every view, and the api branch of
    # current_user used to call a method that only exists on the controller.
    @request.host = "api.example.com"

    get :new

    assert_response :success
  end

  test "should sign in over http basic on the api subdomain" do
    @request.host = "api.example.com"
    @request.headers["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic
      .encode_credentials(@user.email, default_password)

    get :new

    assert_redirected_to root_url
    assert_equal @user, @controller.send(:current_user)
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
