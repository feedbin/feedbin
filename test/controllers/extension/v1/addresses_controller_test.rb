require "test_helper"

class Extension::V1::AddressesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @request.headers["Content-Type"] = "application/json"
  end

  test "should get new when authenticated with email and password" do
    get :new, params: {page_token: @user.page_token}, format: :json
    assert_response :success

    json = JSON.parse(@response.body)
    assert json["token"].present?
    assert json["verified_token"].present?
    assert json["email"].present?
    assert json["addresses"].is_a?(Array)
    assert json["tags"].is_a?(Array)
  end

  test "should return unauthorized for new without authentication" do
    get :new, format: :json
    assert_response :unauthorized
  end

  test "should create newsletter address with save action" do
    token = AuthenticationToken.generate_alpha_token
    verified_token = Rails.application.message_verifier(:address_token).generate(token)
    description = "Test Newsletter"

    assert_difference -> {AuthenticationToken.newsletters.count}, +1 do
      post :create, params: {
        button_action: "save",
        verified_token: verified_token,
        description: description,
        page_token: @user.page_token
      }, format: :json
    end

    assert_response :success

    json = JSON.parse(@response.body)
    assert json["created"]
    assert json["email"].present?
    assert json["addresses"].is_a?(Array)

    created_token = AuthenticationToken.newsletters.find_by(token: token)
    assert_equal description, created_token.description
  end

  test "should preview custom address" do
    post :create, params: {
      button_action: "preview",
      address: "my-custom-address",
      page_token: @user.page_token
    }, format: :json

    assert_response :success

    json = JSON.parse(@response.body)
    assert json["token"].present?
    assert json["verified_token"].present?
    assert json["numbers"].present?
    assert_match /^my-custom-address\.\d+$/, json["token"]
  end

  test "should preview custom address with special characters cleaned" do
    post :create, params: {
      button_action: "preview",
      address: "My@Custom!Address#123",
      page_token: @user.page_token
    }, format: :json

    assert_response :success

    json = JSON.parse(@response.body)
    assert json["token"].present?
    assert_match /^mycustomaddress123\.\d+$/, json["token"]
  end

  test "should return error for preview with empty address" do
    post :create, params: {
      button_action: "preview",
      address: "",
      page_token: @user.page_token
    }, format: :json

    assert_response :bad_request

    json = JSON.parse(@response.body)
    assert json["error"]
  end

  test "should return error for preview with invalid characters only" do
    post :create, params: {
      button_action: "preview",
      address: "@#$%^&*()",
      page_token: @user.page_token
    }, format: :json

    assert_response :bad_request

    json = JSON.parse(@response.body)
    assert json["error"]
  end

  test "should set CORS headers" do
    get :new, params: {page_token: @user.page_token}, format: :json
    assert_equal "*", @response.headers["Access-Control-Allow-Origin"]
    assert_equal "POST, OPTIONS", @response.headers["Access-Control-Allow-Methods"]
  end
end