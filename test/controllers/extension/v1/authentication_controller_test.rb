require "test_helper"

class Extension::V1::AuthenticationControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @request.headers["Content-Type"] = "application/json"
  end

  test "authenticates with email and password" do
    post :index, params: {email: @user.email, password: default_password}, format: :json
    assert_response :success
  end

  test "authenticates with page token" do
    post :index, params: {page_token: @user.page_token}, format: :json
    assert_response :success
  end

  test "authenticates when signed in" do
    login_as @user
    post :index, format: :json
    assert_response :success
  end

  test "returns unauthorized without authentication" do
    post :index, format: :json
    assert_response :unauthorized
  end

  test "returns unauthorized with invalid credentials" do
    post :index, params: {email: @user.email, password: "invalid"}, format: :json
    assert_response :unauthorized
  end

  test "returns not found with invalid page token" do
    post :index, params: {page_token: "invalid_token"}, format: :json
    assert_response :unauthorized
  end

  test "sets CORS headers" do
    post :index, params: {email: @user.email, password: default_password}, format: :json
    assert_equal "*", @response.headers["Access-Control-Allow-Origin"]
    assert_equal "POST, OPTIONS", @response.headers["Access-Control-Allow-Methods"]
  end

end