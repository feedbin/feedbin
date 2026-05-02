require "test_helper"

class Api::V1::ApiControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    Rails.application.routes.draw do
      get "/api/v1/gone", to: "api/v1/api#gone"
    end
  end

  teardown do
    Rails.application.reload_routes!
  end

  test "gone responds with 410 and the API V2 upgrade message" do
    login_as @user
    get :gone
    assert_response :gone
    body = JSON.parse(@response.body)
    assert_equal 410, body["status"]
    assert_match(/V2/i, body["message"])
  end
end
